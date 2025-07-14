public with sharing class UTXOAssetSelector {
    public static List<UTXO_Asset__c> getAssetsByWalletId(String walletId) {
        return [
            SELECT Id, UTXO_Address__c, Asset__c, Amount__c, Name__c, 
                    Decimals__c, Policy_ID__c, Fingerprint__c,
                    UTXO_Address__r.Address__c, UTXO_Address__r.Index__c
            FROM UTXO_Asset__c
            WHERE UTXO_Address__r.Wallet__c = :walletId
            WITH SECURITY_ENFORCED
            ORDER BY UTXO_Address__r.Index__c, Asset__c
        ];
    }
} 