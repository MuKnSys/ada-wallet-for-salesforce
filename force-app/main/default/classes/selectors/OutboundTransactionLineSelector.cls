public with sharing class OutboundTransactionLineSelector {
    public static List<Outbound_Transaction_Line__c> getTransactionLinesByOutboundId(Id outboundTransactionId) {
        return [
            SELECT Id, Amount__c, Asset__c
            FROM Outbound_Transaction_Line__c
            WHERE Outbound_Transaction__c = :outboundTransactionId
            WITH SECURITY_ENFORCED
            ORDER BY Id
        ];
    }
} 