public with sharing class OutboundTransactionSelector {
    public static List<Outbound_Transaction__c> getTransactionsReadyToSendByIds(Set<Id> recordIds) {
        return [
            SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c, Transaction_Hash__c
            FROM Outbound_Transaction__c 
            WHERE Id IN :recordIds
            AND Transaction_Status__c = :ConstantsAda.STATUS_READY_TO_SEND
            WITH SECURITY_ENFORCED
        ];
    }

    public static List<Outbound_Transaction__c> getOutboundTransactionById(Id transactionId) {
        return [
            SELECT Id, To_Address__c, Wallet__c, Memo__c, Signed_Transaction_CBOR__c, Transaction_Status__c
            FROM Outbound_Transaction__c
            WHERE Id = :transactionId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    public static List<Outbound_Transaction__c> getOutboundTransactionsByWalletId(Id walletId) {
        return [
            SELECT Id, Name, Transaction_Hash__c, Transaction_Status__c, Memo__c, CreatedDate,
                    (SELECT Id, Asset__c, Amount__c FROM Outbound_Transaction_Lines__r)
            FROM Outbound_Transaction__c
            WHERE Wallet__c = :walletId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
        ];
    }
} 