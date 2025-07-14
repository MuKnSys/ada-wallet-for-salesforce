public with sharing class OutboundTransactionSelector {
    public static List<Outbound_Transaction__c> getTransactionsReadyToSendByIds(Set<Id> recordIds) {
        return [
            SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c, Transaction_Hash__c
            FROM Outbound_Transaction__c 
            WHERE Id IN :recordIds
            AND Transaction_Status__c = :OutboundTransactionHelper.STATUS_READY_TO_SEND
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


} 