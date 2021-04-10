FROM alpine:latest
RUN apk add --no-cache bash
RUN apk update && apk upgrade && \
    apk add --update curl && \
    apk add --update make && \
    apk add --update git && \
    apk add --update jq
RUN sh -c "curl -s https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash && \
    mv ./kustomize /usr/local/bin/kustomize && chmod +x /usr/local/bin/kustomize"
RUN sh -c "curl -SL https://github.com/GoogleContainerTools/kpt/releases/download/v0.37.0/kpt_linux_amd64-0.37.0.tar.gz | tar xz && \
    mv ./kpt /usr/local/bin/kpt && chmod +x /usr/local/bin/kpt"
RUN sh -c "curl -SL https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz | tar xz && \
    mv ./kubeval /usr/local/bin/kubeval && chmod +x /usr/local/bin/kubeval"
RUN sh -c "curl -SL https://github.com/istio/istio/releases/download/1.5.10/istio-1.5.10-linux.tar.gz | tar xz && \
    mv ./istio-1.5.10/bin/istioctl /usr/local/bin/istioctl && chmod +x /usr/local/bin/istioctl"
RUN sh -c "curl -SL https://github.com/zegl/kube-score/releases/download/v1.10.0/kube-score_1.10.0_linux_amd64 --output kube-score && \
    mv ./kube-score /usr/local/bin/kube-score && chmod +x /usr/local/bin/kube-score"
ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache python3 && ln -sf python3 /usr/bin/python
RUN python3 -m ensurepip
RUN pip3 install --no-cache --upgrade --proxy http://vfukukproxy.internal.vodafone.com:8080 pip setuptools yq
RUN sh -c "curl -SL https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz | tar xz && \
    ./google-cloud-sdk/install.sh"
ENV PATH $PATH:/google-cloud-sdk/bin
