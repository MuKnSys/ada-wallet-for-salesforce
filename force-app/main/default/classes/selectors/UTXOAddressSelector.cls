public with sharing class UTXOAddressSelector {    
    public static List<UTXO_Address__c> getAddressesByWalletId(String walletId) {
        return [
            SELECT Id, Name, Address__c, Is_Used__c, Public_Key__c, Path__c, Index__c, Type__c, Private_Key__c, Payment_Key_Hash__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            WITH SECURITY_ENFORCED
            ORDER BY Type__c, Index__c
        ];
    }

    public static List<UTXO_Address__c> getAddressesByIds(List<Id> addressIds) {
        return [
            SELECT Id, Wallet__c, Is_Used__c, Address__c
            FROM UTXO_Address__c
            WHERE Id IN :addressIds
            WITH SECURITY_ENFORCED
        ];
    }

    public static List<UTXO_Address__c> getLastUTXOAddressByType(String walletId, String type) {
        return [
            SELECT Id, Name, Address__c, Public_Key__c, Path__c, Index__c, Type__c, Private_Key__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            AND Type__c = :type
            WITH SECURITY_ENFORCED
            ORDER BY Index__c DESC
            LIMIT 1
        ];
    }

    public static List<UTXO_Address__c> getFirstUnusedAddressByType(String walletId, String type) {
        return [
            SELECT Address__c, Index__c
            FROM UTXO_Address__c
            WHERE Wallet__c = :walletId
            AND Type__c = :type
            AND (Is_Used__c = false OR Is_Used__c = null)
            WITH SECURITY_ENFORCED
            ORDER BY Index__c
            LIMIT 1
        ];
    }
} 