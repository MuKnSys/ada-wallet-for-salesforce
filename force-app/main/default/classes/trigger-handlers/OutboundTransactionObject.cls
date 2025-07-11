public with sharing class OutboundTransactionObject extends TriggerHandlerADA {

    private static final String STATUS_READY_TO_SEND = 'Ready to send';
    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String APPROVAL_STATUS_APPROVED = 'Approved';

    private static final Integer MIN_TRANSACTION_HASH_LENGTH = 64;

    public override void afterUpdate(List<SObject> records) {        
        collectTransactionsForSubmit((List<Outbound_Transaction__c>) records, (Map<Id, Outbound_Transaction__c>) Trigger.oldMap);
    }
    
    public static void collectTransactionsForSubmit(List<Outbound_Transaction__c> newRecords, Map<Id, Outbound_Transaction__c> oldMap) {
        Set<Id> recordsToSubmit = new Set<Id>();
        
        for (Outbound_Transaction__c newRecord : newRecords) {
            if (shouldSubmitTransaction(newRecord, oldMap)) {
                recordsToSubmit.add(newRecord.Id);
            }
        }
        
        if (!recordsToSubmit.isEmpty()) {
            submitTransactionsAsync(new List<Id>(recordsToSubmit));
        }
    }
    
    private static Boolean shouldSubmitTransaction(Outbound_Transaction__c newRecord, Map<Id, Outbound_Transaction__c> oldMap) {
        Outbound_Transaction__c oldRecord = oldMap?.get(newRecord.Id);
        
        return newRecord.Transaction_Status__c == STATUS_READY_TO_SEND && 
                newRecord.Approved__c == APPROVAL_STATUS_APPROVED &&
                String.isNotBlank(newRecord.Signed_Transaction_CBOR__c) &&
                String.isBlank(newRecord.Transaction_Hash__c) &&
                (oldRecord == null || 
                oldRecord.Transaction_Status__c != STATUS_READY_TO_SEND || 
                oldRecord.Approved__c != APPROVAL_STATUS_APPROVED);
    }
    

    

    
    @future(callout=true)
    public static void submitTransactionsAsync(List<Id> recordIds) {
        List<Outbound_Transaction__c> transactionsToSubmit = [
            SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c, Transaction_Hash__c
            FROM Outbound_Transaction__c 
            WHERE Id IN :recordIds
            AND Transaction_Status__c = 'Ready to send'
        ];
        
        List<Outbound_Transaction__c> transactionsToUpdate = new List<Outbound_Transaction__c>();
        
        for (Outbound_Transaction__c txRecord : transactionsToSubmit) {
            try {
                if (String.isBlank(txRecord.Signed_Transaction_CBOR__c)) {
                    txRecord.Transaction_Status__c = STATUS_READY_TO_SEND;
                    transactionsToUpdate.add(txRecord);
                    continue;
                }
                
                String blockfrostResponse = BlockfrostService.submitTransaction(txRecord.Signed_Transaction_CBOR__c);
                updateTransactionStatus(txRecord, blockfrostResponse);
                transactionsToUpdate.add(txRecord);
                
            } catch (Exception e) {
                // Set status to Rejected on submission error, but do NOT clear CBOR value
                txRecord.Transaction_Status__c = STATUS_REJECTED;
                transactionsToUpdate.add(txRecord);
            }
        }
        
        if (!transactionsToUpdate.isEmpty()) {
            update transactionsToUpdate;
        }
    }
    
    private static void updateTransactionStatus(Outbound_Transaction__c txRecord, String blockfrostResponse) {
        if (blockfrostResponse.startsWith('{')) {
            // JSON error response
            Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(blockfrostResponse);
            String errorMessage = (String) errorResponse.get('error');
            
            // Set status to Rejected on Blockfrost error, but do NOT clear CBOR value
            txRecord.Transaction_Status__c = STATUS_REJECTED;
        } else {
            // Success response - Blockfrost returns the transaction hash as plain text
            String transactionHash = blockfrostResponse.trim();
            
            // Check if we received a valid transaction hash
            if (String.isNotBlank(transactionHash) && transactionHash.length() >= MIN_TRANSACTION_HASH_LENGTH) {
                // Set Transaction_Status to "Sent" and store the transaction hash
                txRecord.Transaction_Status__c = STATUS_SENT;
                txRecord.Transaction_Hash__c = transactionHash;
            } else {
                // Set status to Rejected on invalid hash, but do NOT clear CBOR value
                txRecord.Transaction_Status__c = STATUS_REJECTED;
            }
        }
    }
}
