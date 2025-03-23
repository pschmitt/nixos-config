# pschmitt's nixos book of horrors

Description: tdb.


## Deploying a new host

To create a new host:

- Add it to [flake.nix](./flake.nix)
- Create the config files:

```shell
# nix config
mkdir -p ./hosts/$NEW_HOST
cp ./hosts/rofl-05/*.nix ./hosts/$NEW_HOST
./secrets/sops-init.sh $NEW_HOST

# create tofu config
cp -a ./tofu/rofl-05.tf ./tofu/${NEW_HOST}.tf
```

- To deploy:
```shell
./tofu/tofu.sh init
./tofu/tofu.sh apply -target=openstack_compute_instance_v2.${NEW_HOST} -target=module.nix-${NEW_HOST}
```
