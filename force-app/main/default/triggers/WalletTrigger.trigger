trigger WalletTrigger on Wallet__c (before insert, before update) {
    if (TriggerSettings.walletTrigger) {
        new Wallet().onTrigger();
    }
}