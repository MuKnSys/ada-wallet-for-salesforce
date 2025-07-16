public with sharing class UTXOAssetSelector {
    public static List<UTXO_Asset__c> getAllAssetsByUtxoAddressIds(Set<Id> utxoAddressIds) {
        return [
            SELECT Id, Asset__c, Amount__c, Value__c, Name__c, Decimals__c, 
                    Policy_ID__c, Fingerprint__c, Icon__c, UTXO_Address__c
            FROM UTXO_Asset__c
            WHERE UTXO_Address__c IN :utxoAddressIds
            WITH SECURITY_ENFORCED
            ORDER BY Asset__c
        ];
    }

    public static AggregateResult[] getAssetAggregatesByUtxoAddressIds(Set<Id> utxoAddressIds) {
        return [
            SELECT Asset__c, SUM(Amount__c) totalAmount, SUM(Value__c) totalValue, 
                    MAX(Name__c) assetName, 
                    MAX(Decimals__c) decimals, MAX(Policy_ID__c) policyId,
                    MAX(Fingerprint__c) fingerprint
            FROM UTXO_Asset__c
            WHERE UTXO_Address__c IN :utxoAddressIds
            WITH SECURITY_ENFORCED
            GROUP BY Asset__c
            ORDER BY Asset__c
        ];
    }
} 