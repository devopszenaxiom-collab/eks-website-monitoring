# State lives in a storage account, one state file per cluster, so one client's
# install can never touch another's. The pipeline passes the account, container
# and key with -backend-config; nothing is hard-coded here.
terraform {
  backend "azurerm" {}
}
