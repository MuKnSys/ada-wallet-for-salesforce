public with sharing class WalletSelector {
    @AuraEnabled
    public static Wallet__c getWalletById(Id walletId) {
        return [SELECT Id, Wallet_Set__c, Account_Private_Key__c, Account_Public_Key__c, Account_Index__c FROM Wallet__c WHERE Id = :walletId LIMIT 1];
    }
}