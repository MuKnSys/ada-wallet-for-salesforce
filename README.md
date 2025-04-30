# ADA Wallet for Salesforce

## Development

1. **If you are not authorised to dev hub** run `sf org login web --set-default-dev-hub --alias DevHub --instance-url DevHubURL`
    - flag `--set-default-dev-hub` marks dev hub as default. If not set it will be required to provide dev hub in some commands like create scratch org
    - flag `--alias` is an alias of the org. You can set some friendly name so you can easily reference that org
    - flag `--instance-url` allows you to provide specific URL to log into in case you are authorised in multiple orgs
      \*\*If you are already logged in but need to update the Dev Hub, you can use sf config set target-dev-hub DevHub --global
1. Check out `develop` branch
1. Create a new `feature` branch e.g. `feature/mukn-123`
1. Create a scratch org by running `sf org create scratch -f ./config/project-scratch-def.json -a dev -d -y 30`
    - flag `-f` is a path to config file (no need to change it)
    - flag `-a` is an alias of the scratch org, if you create multiple scratch orgs you can give them unique aliases to easier refer to them
    - flag `-d` marks the newly created scratch org as default. If you don't mark it as default you will have to reference it by username or alias, or you will have to use `sf config set target-org YourAliasOrUsername` to set is as default
    - flag `-y` sets the number of days before org expires
    - use `-h` flag for help
1. Push code to newly created scratch org by using `sf project deploy start`
1. Add the Admin Permissions to this user `sf org assign permset --name Ada_Wallet_Admin_Managed`
1. Connect into the Org: `sf org open`
1. To preload the AssetToken and TokenContract information in a development org, go into the Salesforce Debugger and execute: `PostInstall postInstallHandler = new PostInstall(); postInstallHandler.installDefaultAssetsAndContracts();`
1. Introduce changes (deploy to scratch org if code was changed)
1. If any changes were introduced directly in scratch org pull them using `sf project retrieve start`
1. To check if there are any changes run `sf project retrieve preview` and `sf project deploy preview`
1. Commit changes to feature branch. Provide meaningful commit message like `mukn-123: unit tests`
1. After finished development create a Pull Request back to `develop` branch

## Additional resources

-   [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
-   [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
-   [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
-   [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
-   [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm)
