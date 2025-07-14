public with sharing class UTXOAddressSelector {    
    public static List<UTXO_Address__c> getUTXOAddressesByWalletId(Id walletId, Set<String> types) {
        String query = 'SELECT Id, Name, Address__c, Is_Used__c, Public_Key__c, Path__c, Index__c, Type__c, Private_Key__c' + 
            ' FROM UTXO_Address__c' +
            ' WHERE Wallet__c = :walletId';
            
        if (types != null && !types.isEmpty()) {
            query += ' AND Type__c IN :types';
        }
        
        query += ' WITH SECURITY_ENFORCED ORDER BY Name ASC';
        return Database.query(query);
    }

    public static List<UTXO_Address__c> getLastUTXOAddressByType(Id walletId, String type) {
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
} 