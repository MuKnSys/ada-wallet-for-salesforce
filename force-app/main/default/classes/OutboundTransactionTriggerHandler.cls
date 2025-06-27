public class OutboundTransactionTriggerHandler {
    
    public static void handleBeforeUpdate(List<Outbound_Transaction__c> newRecords, Map<Id, Outbound_Transaction__c> oldMap) {
        List<Id> recordsToSubmit = new List<Id>();
        for (Outbound_Transaction__c newRecord : newRecords) {
            try {
                Outbound_Transaction__c oldRecord = oldMap.get(newRecord.Id);
                
                // Check if Transaction_Status moved to "Ready to send" and Approved is "Approved"
                if (newRecord.Transaction_Status__c == 'Ready to send' && 
                    newRecord.Approved__c == 'Approved' &&
                    (oldRecord == null || oldRecord.Transaction_Status__c != 'Ready to send' || oldRecord.Approved__c != 'Approved')) {
                    
                    // Check if CBOR is available (immediate validation)
                    if (String.isNotBlank(newRecord.Signed_Transaction_CBOR__c)) {
                        System.debug('OutboundTransactionTrigger: Queueing transaction for submission to Blockfrost for record: ' + newRecord.Id);
                        
                        // Queue for async submission - let Blockfrost API handle validation
                        recordsToSubmit.add(newRecord.Id);
                        
                        // Keep status as "Ready to send" - async method will handle status changes
                        System.debug('OutboundTransactionTrigger: Record queued for submission: ' + newRecord.Id);
                    } else {
                        System.debug('OutboundTransactionTrigger: No CBOR available for record: ' + newRecord.Id);
                        
                        // Add error to record to prevent save and show error to user
                        String noCborError = 'Transaction submission failed: No signed transaction CBOR available. Please rebuild and sign the transaction first.';
                        newRecord.addError('Transaction_Status__c', noCborError);
                    }
                }
            } catch (Exception e) {
                System.debug('OutboundTransactionTrigger: Exception processing record ' + newRecord.Id + ': ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
                
                // Add error to record to prevent save and show error to user
                String unexpectedError = 'Transaction submission failed: ' + e.getMessage();
                newRecord.addError('Transaction_Status__c', unexpectedError);
            }
        }
        
        // Submit transactions asynchronously if any were queued
        if (!recordsToSubmit.isEmpty()) {
            System.debug('OutboundTransactionTrigger: Submitting ' + recordsToSubmit.size() + ' transactions asynchronously');
            submitTransactionsAsync(recordsToSubmit);
        }
        
        System.debug('OutboundTransactionTrigger: Processed ' + newRecords.size() + ' records');
    }
    
    @future(callout=true)
    public static void submitTransactionsAsync(List<Id> recordIds) {
        System.debug('submitTransactionsAsync: Processing ' + recordIds.size() + ' transactions');
        
        // Query the records to get their CBOR data
        List<Outbound_Transaction__c> transactionsToSubmit = [
            SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c, Transaction_Hash__c
            FROM Outbound_Transaction__c 
            WHERE Id IN :recordIds
            AND Transaction_Status__c = 'Ready to send'
        ];
        
        List<Outbound_Transaction__c> transactionsToUpdate = new List<Outbound_Transaction__c>();
        
        for (Outbound_Transaction__c txRecord : transactionsToSubmit) {
            try {
                // Check if CBOR is still available
                if (String.isBlank(txRecord.Signed_Transaction_CBOR__c)) {
                    System.debug('submitTransactionsAsync: No CBOR available for transaction ' + txRecord.Id);
                    // Set status back to "Ready to send" since CBOR is missing
                    txRecord.Transaction_Status__c = 'Ready to send';
                    transactionsToUpdate.add(txRecord);
                    continue;
                }
                
                System.debug('submitTransactionsAsync: Submitting transaction ' + txRecord.Id + ' to Blockfrost');
                
                // Call Blockfrost API to submit the transaction
                String blockfrostResponse = BlockfrostService.submitTransaction(txRecord.Signed_Transaction_CBOR__c);
                
                System.debug('submitTransactionsAsync: Blockfrost response for ' + txRecord.Id + ': ' + blockfrostResponse);
                
                // Parse the response from Blockfrost
                if (blockfrostResponse.startsWith('{')) {
                    // JSON error response
                    Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(blockfrostResponse);
                    String errorMessage = (String) errorResponse.get('error');
                    System.debug('submitTransactionsAsync: Blockfrost API error for ' + txRecord.Id + ': ' + errorMessage);
                    
                    // Set status back to "Ready to send" so user can retry
                    txRecord.Transaction_Status__c = 'Ready to send';
                    transactionsToUpdate.add(txRecord);
                    
                } else {
                    // Success response - Blockfrost returns the transaction hash as plain text
                    String transactionHash = blockfrostResponse.trim();
                    
                    System.debug('submitTransactionsAsync: Raw transaction hash received for ' + txRecord.Id + ': ' + transactionHash);
                    
                    // Check if we received a valid transaction hash (not empty and reasonable length)
                    if (String.isNotBlank(transactionHash) && transactionHash.length() >= 64) {
                        // Set Transaction_Status to "Sent" and store the transaction hash
                        txRecord.Transaction_Status__c = 'Sent';
                        txRecord.Transaction_Hash__c = transactionHash;
                        transactionsToUpdate.add(txRecord);
                        
                        System.debug('submitTransactionsAsync: ✅ Transaction ' + txRecord.Id + ' sent successfully. Hash: ' + transactionHash);
                    } else {
                        System.debug('submitTransactionsAsync: ❌ Invalid or empty transaction hash received for ' + txRecord.Id + ': ' + transactionHash);
                        
                        // Set status back to "Ready to send" so user can retry
                        txRecord.Transaction_Status__c = 'Ready to send';
                        transactionsToUpdate.add(txRecord);
                    }
                }
            } catch (Exception e) {
                System.debug('submitTransactionsAsync: Exception processing transaction ' + txRecord.Id + ': ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
                
                // Set status back to "Ready to send" so user can retry
                txRecord.Transaction_Status__c = 'Ready to send';
                transactionsToUpdate.add(txRecord);
            }
        }
        
        // Update all transactions with their final status
        if (!transactionsToUpdate.isEmpty()) {
            try {
                update transactionsToUpdate;
                System.debug('submitTransactionsAsync: Updated ' + transactionsToUpdate.size() + ' transaction records');
                
                // Log final status for each updated record
                for (Outbound_Transaction__c updatedRecord : transactionsToUpdate) {
                    System.debug('submitTransactionsAsync: Record ' + updatedRecord.Id + ' final status: ' + updatedRecord.Transaction_Status__c);
                }
            } catch (Exception e) {
                System.debug('submitTransactionsAsync: Error updating transaction records: ' + e.getMessage());
            }
        }
    }
} 