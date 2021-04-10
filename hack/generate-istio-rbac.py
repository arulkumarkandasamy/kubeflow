import yaml
import os
from jinja2 import Environment, FileSystemLoader


def find_matching_service(deployment_yaml):
    # print(deployment_yaml['metadata']['labels']['app'])
    for root, _, files in os.walk("../deployments/vf-dev-nwp-nonlive/gcp_iap/build/kubeflow-apps"):
        for file in files:
            if '_service_' in file:
                resource_yaml = yaml.load(open(root + '/' + file, 'r+'))
                if match_labels(deployment_yaml, resource_yaml):
                    return root + '/' + file
    return None


def match_labels(deployment_yaml, service_yaml):
    deployment_selector_labels = deployment_yaml['spec']['selector']['matchLabels']
    service_selector_labels = service_yaml['spec']['selector']
    if deployment_selector_labels == service_selector_labels:
        return True
    # print(deployment_selector_labels)
    # print(service_selector_labels)


def create_patch():
    patch = dict()
    patch["op"] = "remove"
    patch["path"] = "spec/template/metadata/annotations/sidecar.istio.io~1inject"
    to_return = list()
    to_return.append(patch)
    return to_return


def edit_kustomization(deployment_name, patch_path):
    kustomization = yaml.load(open("../manifests/stacks/vf-stack/kustomization.yaml", "r"))
    patches_list = kustomization['patchesJson6902']
    if patches_list is None:
        patches_list = list()
    target = dict()
    target["target"] = dict()
    target["target"]["group"] = "apps.k8s.io"
    target["target"]["version"] = "v1"
    target["target"]["kind"] = "Deployment"
    target["target"]["name"] = deployment_name
    target["path"] = patch_path
    patches_list.append(target)
    kustomization['patchesJson6902'] = patches_list
    yaml.dump(kustomization, open("../manifests/stacks/vf-stack/kustomization.yaml", "w"))


def generate_istio_patches(deployment_yamls):
    istio_inject_patch_location = "../manifests/stacks/vf-stack/patches/istio-inject-patches"
    for deployment_yaml in deployment_yamls:
        patch_name = ((os.path.basename(deployment_yaml).replace(".yaml", "")) + '-patch.yaml').replace(
            "apps_v1_deployment_", "")
        patch = create_patch()
        yaml.dump(patch, open(istio_inject_patch_location + "/" + patch_name, "w+"))
        deployment_yaml = yaml.load(open(deployment_yaml, "r"))
        edit_kustomization(deployment_yaml["metadata"]["name"],
                           ('.' + istio_inject_patch_location + "/" + patch_name).replace(
                               '../manifests/stacks/vf-stack', ''))


def generate_istio_rbac(items):
    file_loader = FileSystemLoader('templates')
    env = Environment(loader=file_loader)
    template = env.get_template("istio-rbac.j2")
    for item in items:
        if item["service_yaml"] is not None:
            file_name = ((os.path.basename(item["deployment_yaml"]).replace(".yaml", "")) + '-istio-rbac.yaml').replace(
                "apps_v1_deployment_", "")
            print(file_name)
            app_name = yaml.load(open(item["deployment_yaml"]))["metadata"]["name"]
            print(app_name)
            service_name = yaml.load(open(item["service_yaml"]))["metadata"]["name"]
            output = template.render(app_name=app_name, service_name=service_name)
            with open("../manifests/stacks/vf-stack/istio-rbac/" + file_name, "w") as fh:
                fh.write(output)


def main():
    items = list()
    deployment_yamls = list()
    for root, _, files in os.walk("../deployments/vf-dev-nwp-nonlive/gcp_iap/build/kubeflow-apps"):
        for file in files:
            if 'deployment' in file:
                resource_yaml = yaml.load(open(root + '/' + file, 'r+'))
                try:
                    if resource_yaml['spec']['template']['metadata']['annotations']["sidecar.istio.io/inject"] == \
                            "false":
                        print('Deployment yaml:')
                        print(root + '/' + file)
                        service_yaml = find_matching_service(resource_yaml)
                        print('Service yaml:')
                        print(service_yaml)
                        print('=============================')
                        deployment_yamls.append(root + '/' + file)
                        items.append({
                            'deployment_yaml': root + '/' + file,
                            'service_yaml': service_yaml
                        })
                except KeyError as e:
                    pass
    print("Generating istio patches")
    generate_istio_patches(deployment_yamls)
    print("Generating istio RBAC resources")
    generate_istio_rbac(items)


if __name__ == '__main__':
    main()
