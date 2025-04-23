public with sharing class UTXOAddressSelector {
    public static List<UTXO_Address__c> getUTXOAddressesByWalletId(String walletId) {
        return [
            SELECT Id, Name, Address__c, Public_Key__c, Path__c, Staking_Key_Hash__c, Index__c, Type__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
        ];
    }

    public static List<UTXO_Address__c> getUTXOAddressesByWalletIdAndType(String walletId, String type) {
        return [
            SELECT Index__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            AND Type__c = :type
            WITH SECURITY_ENFORCED
            ORDER BY Index__c DESC
            LIMIT 1
        ];
    }
} 