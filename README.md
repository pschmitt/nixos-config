# pschmitt's nixos book of horrors

Description: tdb.


## Deploying a new host

To create a new host:

- Add it to [flake.nix](./flake.nix)
- Create the config files:

```shell
mkdir -p ./hosts/$NEW_HOST

cp ./hosts/rofl-05/*.nix ./hosts/$NEW_HOST

# create secrets
./secrets/sops-init.sh $NEW_HOST
```

- To deploy:
```shell
./tofu/tofu.sh apply -target=module.nix-${NEW_HOST}
```
