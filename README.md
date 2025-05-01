# ADA Wallet for Salesforce

![](documentation-and-images/ADA-Wallet-for-Salesforce-thumbnail.png)
The public repository for the Cardano Catalyst Fund 13 project


## Installation Instructions / How to Test the App

1. Clone the repository. `git clone https://github.com/MuKnSys/ada-wallet-for-salesforce.git`
2. Check out the main branch.
3. Log into the Dev Hub Org by running `sf org login web --set-default-dev-hub --alias DevHub --instance-url https://login.salesforce.com` and entering your username and password.
4. Create a Scratch Org by running `sf org create scratch -f ./config/project-scratch-def.json -a dev -d -y 30`.
* The `-f` flag is a path to config file (no need to change it).
* The `-a` flag is an alias of the scratch org, if you create multiple scratch orgs you can give them unique aliases to easier refer to them.
* The `-d` flag marks the newly created scratch org as default. If you don't mark it as default you will have to reference it by username or alias, or you will have to use `sf config set target-org YourAliasOrUsername` to set is as default.
* The `-y` flag sets the number of days before the org expires.
* Use the `-h` flag for help.
* For more details: [developer docs scratch orgs create](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_scratch_orgs_create.htm).
11. Push the code to the Scratch Org: `sf project deploy start`
12. Connect to the Salesforce Scratch Org: `sf org open`


## Copyright and Licence

Copyright 2024 Web3 Enabler, Inc. ADA Wallet for Salesforce is distributed under the GPL licence, version 3.0. For more information, see the [LICENSE](LICENSE) file.
