public with sharing class InboundTransactionSelector {
    public static List<Inbound_Transaction__c> getInboundTransactionsByUtxoAddressId(Id utxoAddressId) {
        return [
            SELECT Id, Transaction_Hash__c, Block_Height__c, Block_Time__c, Transaction_Index__c
            FROM Inbound_Transaction__c
            WHERE UTXO_Address__c = :utxoAddressId
            WITH SECURITY_ENFORCED
        ];
    }

    public static List<Inbound_Transaction__c> getInboundTransactionsByWalletId(Id walletId) {
        return [
            SELECT Id, Name, Transaction_Hash__c, CreatedDate, UTXO_Address__c
            FROM Inbound_Transaction__c
            WHERE UTXO_Address__r.Wallet__c = :walletId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ];
    }
} 