trigger WalletTrigger on Wallet__c (before insert, before update) {
    if (TriggerSettingsADA.walletTrigger) {
        new WalletObject().onTrigger();
    }
}