public with sharing class WalletSelector {
    public static Wallet__c getWalletById(Id walletId) {
        return [SELECT Id, Wallet_Set__c FROM Wallet__c WHERE Id = :walletId LIMIT 1];
    }
}