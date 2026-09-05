# build-images

Custom Fedora images for Incus container, built with
[distrobuilder](https://linuxcontainers.org/distrobuilder/docs/latest/) from
`fedora.yaml`.

Build and import them with:

```sh
$ mise install
$ mise run build-lxc
$ mise run import-lxc-image-to-incus1-registry
```

