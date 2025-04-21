public with sharing class UTXOController {
    public class UTXOAddress {
        @AuraEnabled public Integer index { get; set; }
        @AuraEnabled public String publicKey { get; set; }
        @AuraEnabled public String address { get; set; }
        @AuraEnabled public String stakingKeyHash { get; set; }
        @AuraEnabled public String path { get; set; }
        @AuraEnabled public String stakePath { get; set; }
    }

    @AuraEnabled
    public static void createUTXOAddresses(String walletId, List<UTXOAddress> receivingAddresses, List<UTXOAddress> changeAddresses) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (receivingAddresses == null || changeAddresses == null) {
                throw new AuraHandledException('Address lists cannot be null');
            }

            // Prepare UTXO_Address__c records
            List<UTXO_Address__c> utxoRecords = new List<UTXO_Address__c>();

            // Process receiving addresses (Type__c = 0)
            for (UTXOAddress addr : receivingAddresses) {
                if (addr.index == null || String.isBlank(addr.address) || String.isBlank(addr.publicKey) || String.isBlank(addr.stakingKeyHash) || String.isBlank(addr.path)) {
                    throw new AuraHandledException('Invalid receiving address data for index ' + addr.index);
                }
                utxoRecords.add(new UTXO_Address__c(
                    Wallet__c = walletId,
                    Address__c = addr.address,
                    Index__c = addr.index,
                    Public_Key__c = addr.publicKey,
                    Staking_Key_Hash__c = addr.stakingKeyHash,
                    Path__c = addr.path,
                    Type__c = '0' // Receiving address
                ));
            }

            // Process change addresses (Type__c = 1)
            for (UTXOAddress addr : changeAddresses) {
                if (addr.index == null || String.isBlank(addr.address) || String.isBlank(addr.publicKey) || String.isBlank(addr.stakingKeyHash) || String.isBlank(addr.path)) {
                    throw new AuraHandledException('Invalid change address data for index ' + addr.index);
                }
                utxoRecords.add(new UTXO_Address__c(
                    Wallet__c = walletId,
                    Address__c = addr.address,
                    Index__c = addr.index,
                    Public_Key__c = addr.publicKey,
                    Staking_Key_Hash__c = addr.stakingKeyHash,
                    Path__c = addr.path,
                    Type__c = '1' // Change address
                ));
            }

            // Insert records with security enforcement
            if (!utxoRecords.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, utxoRecords);
                insert decision.getRecords();
                System.debug('UTXOController: Created ' + utxoRecords.size() + ' UTXO_Address__c records for Wallet__c ' + walletId);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error creating UTxO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getUTXOAddresses(String walletId) {
        try {
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            return [
                SELECT Id, Name, Address__c, Public_Key__c, Path__c, Staking_Key_Hash__c, Index__c, Type__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                WITH SECURITY_ENFORCED
                ORDER BY Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO addresses: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getUserPermissions() {
        try {
            List<String> assignedPermissionSets = new List<String>();
            for (PermissionSetAssignment psa : [
                SELECT PermissionSet.Name
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
            ]) {
                assignedPermissionSets.add(psa.PermissionSet.Name);
            }
            return assignedPermissionSets;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving user permissions: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Integer getNextUTXOIndex(String walletId, String type) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (String.isBlank(type) || !(type == '0' || type == '1')) {
                throw new AuraHandledException('Type must be "0" (receiving) or "1" (change)');
            }

            // Query UTXO_Address__c records for the given Wallet__c and Type__c
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Index__c
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
                AND Type__c = :type
                WITH SECURITY_ENFORCED
                ORDER BY Index__c DESC
                LIMIT 1
            ];

            // If no records are found, start at index 0
            if (utxoAddresses.isEmpty()) {
                return 0;
            }

            // Get the highest Index__c and return the next index
            Integer highestIndex = (Integer)utxoAddresses[0].Index__c;
            Integer nextIndex = highestIndex + 1;
            return nextIndex;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving next UTXO index: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void addReceivingUTXOAddress(String walletId, UTXOAddress receivingAddress) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (receivingAddress == null) {
                throw new AuraHandledException('Receiving address cannot be null');
            }
            if (receivingAddress.index == null || String.isBlank(receivingAddress.address) || 
                String.isBlank(receivingAddress.publicKey) || String.isBlank(receivingAddress.stakingKeyHash) || 
                String.isBlank(receivingAddress.path)) {
                throw new AuraHandledException('Invalid receiving address data for index ' + receivingAddress.index);
            }

            // Create a new UTXO_Address__c record for the receiving address (Type__c = 0)
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = receivingAddress.address,
                Index__c = receivingAddress.index,
                Public_Key__c = receivingAddress.publicKey,
                Staking_Key_Hash__c = receivingAddress.stakingKeyHash,
                Path__c = receivingAddress.path,
                Type__c = '0' // Receiving address
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
            System.debug('UTXOController: Created 1 receiving UTXO_Address__c record for Wallet__c ' + walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error adding receiving UTXO address: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void addChangeUTXOAddress(String walletId, UTXOAddress changeAddress) {
        try {
            // Validate inputs
            if (String.isBlank(walletId) || !Pattern.matches('^[a-zA-Z0-9]{15,18}$', walletId)) {
                throw new AuraHandledException('Invalid Wallet ID');
            }
            if (changeAddress == null) {
                throw new AuraHandledException('Change address cannot be null');
            }
            if (changeAddress.index == null || String.isBlank(changeAddress.address) || 
                String.isBlank(changeAddress.publicKey) || String.isBlank(changeAddress.stakingKeyHash) || 
                String.isBlank(changeAddress.path)) {
                throw new AuraHandledException('Invalid change address data for index ' + changeAddress.index);
            }

            // Create a new UTXO_Address__c record for the change address (Type__c = 1)
            UTXO_Address__c utxoRecord = new UTXO_Address__c(
                Wallet__c = walletId,
                Address__c = changeAddress.address,
                Index__c = changeAddress.index,
                Public_Key__c = changeAddress.publicKey,
                Staking_Key_Hash__c = changeAddress.stakingKeyHash,
                Path__c = changeAddress.path,
                Type__c = '1' // Change address
            );

            // Insert the record with security enforcement
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<UTXO_Address__c>{utxoRecord});
            insert decision.getRecords();
            System.debug('UTXOController: Created 1 change UTXO_Address__c record for Wallet__c ' + walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error adding change UTXO address: ' + e.getMessage());
        }
    }
}