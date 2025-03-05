# ssh-punchhole

## Installing the Chart

To install the chart with the release name `my-release`:

```bash
$ helm upgrade \
    --install \
    my-release \
    oci://ghcr.io/tamcore/ssh-punchhole/chart/ssh-punchhole \
    --version 0.0.1
```

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```bash
$ helm delete my-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Parameters

### Image parameters

| Name               | Description       | Value                           |
| ------------------ | ----------------- | ------------------------------- |
| `image.repository` | image repository  | `ghcr.io/tamcore/ssh-punchhole` |
| `image.tag`        | image tag         | `""`                            |
| `image.pullPolicy` | image pull policy | `IfNotPresent`                  |


### Generic parameters

| Name                 | Description                                         | Value |
| -------------------- | --------------------------------------------------- | ----- |
| `replicaCount`       | Number of replicas to deploy                        | `1`   |
| `postStart.command`  | If set, will run the command as a postStart handler | `[]`  |
| `resources.limits`   | The resources limits for the pod                    | `{}`  |
| `resources.requests` | The requested resources for the pod                 | `{}`  |


### Configuration

| Name                              | Description                                                  | Value                                                                                          |
| --------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| `configuration.SSH_PORT`          | SSH Port to connect to                                       | `22`                                                                                           |
| `configuration.SSH_USER`          | User to login as on the remote host                          | `root`                                                                                         |
| `configuration.REMOTE_HOST`       | Remote host to connect to                                    | `pub.example.com`                                                                              |
| `configuration.REMOTE_FORWARD`    | ip:port combinations to open on the remote host              | `0.0.0.0:80 0.0.0.0:443`                                                                       |
| `configuration.LOCAL_DESTINATION` | ip:port combinations to forward traffic to on the local side | `ingress-nginx-controller.ingress-nginx.svc:80 ingress-nginx-controller.ingress-nginx.svc:443` |


### SSH Credentials

| Name                  | Description                                                                         | Value |
| --------------------- | ----------------------------------------------------------------------------------- | ----- |
| `data.privateKey`     | Passwordless OpenSSH Private Key authorized to login as `SSH_USER` on `REMOTE_HOST` | `""`  |
| `data.knownHosts`     | Used for OpenSSH HostKeyVerification. Output of `ssh-keyscan ${REMOTE_HOST}`.       | `""`  |
| `data.existingSecret` | Name of secret containing keys `id_rsa` and `known_hosts`.                          | `""`  |


## License
```
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
```
