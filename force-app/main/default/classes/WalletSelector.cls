public with sharing class WalletSelector {
    public static Wallet__c getWalletById(Id walletId) {
        return [SELECT Id, Wallet_Set__c, Account_Private_Key__c, Account_Public_Key__c, Account_Index__c FROM Wallet__c WHERE Id = :walletId WITH SECURITY_ENFORCED LIMIT 1];
    }
    
    public static List<Wallet__c> getWalletByWalletSetAndAccountIndex(String walletSetId, Integer accountIndex) {
        return [SELECT Id FROM Wallet__c WHERE Wallet_Set__c = :walletSetId AND Account_Index__c = :accountIndex LIMIT 1];
    }

    public static List<Wallet__c> getWalletsExcludingIds(Set<Id> walletIds) {
        return [SELECT Wallet_Set__c, Account_Index__c
            FROM Wallet__c
            WHERE Wallet_Set__c != null AND Account_Index__c != null
            AND Id NOT IN :walletIds
            WITH SECURITY_ENFORCED];
    }
}