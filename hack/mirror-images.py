import yaml
import os
import docker
import argparse
from distutils.dir_util import copy_tree
import shutil
import requests
import json


def mirror_images(images, project):
    client = docker.from_env()
    for task in images:
        input_image = task["image"]
        output_image = task["mirror"]
        print("Input image: " + input_image)
        print("Output image: " + output_image)
        if check_if_in_remote(output_image):
            print("Image is already present in gcr repo")
        else:
            image = client.images.build(path="./", rm=True, buildargs={"INPUT_IMAGE": input_image}, tag=output_image)
            image = image[0]
            image_tag = [tag for tag in image.tags if project in tag][0]
            print("Built: " + str(image.tags[0]) + ". Now pushing to " + image.tags[1])
            for line in client.images.push(image_tag, stream=True, decode=True):
                print(line)


def check_if_in_remote(image_tag):
    tag = image_tag.split(":")[1]
    image = image_tag.split(":")[0]
    access_token = os.popen('gcloud auth print-access-token').read()[:-1]
    current_images = json.loads(requests.get("https://gcr.io/v2/" + image.replace("gcr.io/", "") + "/tags/list",
                                             auth=('_token', access_token)).content)
    if current_images and tag in current_images["tags"]:
        return True
    return False


def cache_kustomize_folder(kustomize_directory):
    abspath = os.path.abspath(kustomize_directory).replace("/kustomize", "")
    if os.path.exists(os.path.join(abspath, ".cache", "kustomize")):
        shutil.rmtree(os.path.join(abspath, ".cache", "kustomize"))
    os.mkdir(os.path.join(abspath, ".cache", "kustomize"))
    copy_tree(kustomize_directory, os.path.join(os.path.join(abspath, ".cache", "kustomize")))


def main(kustomize_directory: str, project: str):
    images = []
    cache_kustomize_folder(kustomize_directory)
    for root, dirs, files in os.walk(kustomize_directory):
        for file in files:
            if file == 'kustomization.yaml':
                loaded_yaml = yaml.safe_load(open(os.path.join(root, file), "r"))
                if "images" in loaded_yaml:
                    for image_ref in loaded_yaml["images"]:
                        if '$(project)' not in image_ref["name"] and image_ref["name"] != "cos-nvidia-installer":
                            new_image_name = "gcr.io/" + project + "/mirror/" + (
                                image_ref["name"].replace("gcr.io/", "").replace("$(registry)", "gcr.io/kfserving"))
                            image_ref["newName"] = new_image_name
                            if "newTag" in image_ref:
                                images.append({
                                    "image": image_ref["name"] + ":" + image_ref["newTag"],
                                    "mirror": new_image_name + ":" + image_ref["newTag"]
                                })
                            else:
                                images.append({
                                    "image": image_ref["name"] + ":v0.11.1",
                                    "mirror": new_image_name + ":v0.11.1"
                                })
                            #  BUG:
                            # - image: gcr.io/kfserving/kfserving-controller:0.2.2 >  gcr.io/vf-mc2dev-ca-lab/mirror/kfserving/kfserving-controller
                #           Deal with SHA - not correct with newTag and digest etc
                yaml.dump(loaded_yaml, open(os.path.join(root, file), "w"))
    mirror_images(images, project)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Set & mirror Docker images from kustomize files.')
    parser.add_argument('kustomizeDirectory', help='path to kustomize directory')
    parser.add_argument('project', help='Project GCR to mirror to')
    args = parser.parse_args()
    try:
        main(args.kustomizeDirectory, args.project)
    except Exception as exc:
        print(type(exc))
        print(exc)
        exit(1)
