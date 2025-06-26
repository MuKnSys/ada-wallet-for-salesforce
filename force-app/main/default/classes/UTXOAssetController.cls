/**
 * UTXOAssetController - Clean controller for UTXO asset and transaction synchronization
 */
public with sharing class UTXOAssetController {
    
    /**
     * Synchronizes assets only for a UTXO address
     * @param utxoAddressId The UTXO Address ID to sync assets for
     * @return Map with asset data and statistics
     */
    @AuraEnabled
    public static Map<String, Object> syncAssets(Id utxoAddressId) {
        try {
            Logger.logInfo('[UTXOAssetController.syncAssets] 🚀 Starting asset sync for address ID: ' + utxoAddressId);
            Long startTime = System.now().getTime();
            
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address ID cannot be null');
            }
            
            // Get the UTXO Address record
            UTXO_Address__c utxoAddress = [
                SELECT Id, Address__c, Wallet__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];
            
            if (utxoAddress == null) {
                throw new AuraHandledException('UTXO Address not found');
            }
            
            Logger.logInfo('[UTXOAssetController.syncAssets] 📍 Processing address: ' + utxoAddress.Address__c);
            
            // Step 1: Get UTXOs from Blockfrost
            String utxoJson = BlockfrostService.getAddressUtxos(utxoAddress.Address__c);
            List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxoJson);
            
            Logger.logInfo('[UTXOAssetController.syncAssets] 📦 Found ' + utxoList.size() + ' UTXOs');
            
            // Step 2: Process and aggregate assets
            Map<String, Decimal> unitToTotalAmount = new Map<String, Decimal>();
            Map<String, String> unitToMetadata = new Map<String, String>();
            Set<String> allUnits = new Set<String>();
            
            // Collect all unique units first
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                List<Object> amounts = (List<Object>) utxo.get('amount');
                if (amounts != null) {
                    for (Object amtObj : amounts) {
                        Map<String, Object> amt = (Map<String, Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        allUnits.add(unit);
                    }
                }
            }
            
            // Step 3: Fetch metadata for all units
            for (String unit : allUnits) {
                if (unit != 'lovelace') {
                    try {
                        String metadata = BlockfrostService.getAssetMetadata(unit);
                        if (metadata != null && metadata != '{}') {
                            unitToMetadata.put(unit, metadata);
                        }
                    } catch (Exception e) {
                        Logger.logError('[UTXOAssetController.syncAssets] ❌ Failed to fetch metadata for unit: ' + unit + ' - ' + e.getMessage());
                    }
                }
            }
            
            // Step 4: Process UTXOs and aggregate amounts
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                List<Object> amounts = (List<Object>) utxo.get('amount');
                if (amounts != null) {
                    for (Object amtObj : amounts) {
                        Map<String, Object> amt = (Map<String, Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        Decimal quantity = Decimal.valueOf(String.valueOf(amt.get('quantity')));
                        
                        if (!unitToTotalAmount.containsKey(unit)) {
                            unitToTotalAmount.put(unit, 0);
                        }
                        unitToTotalAmount.put(unit, unitToTotalAmount.get(unit) + quantity);
                    }
                }
            }
            
            // Step 5: Create/update UTXO_Asset__c records
            List<UTXO_Asset__c> existingAssets = [
                SELECT Id, Unit__c, Amount__c, UTXO_Address__c
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ];
            
            // Create a comprehensive lookup map for existing assets
            // We need to handle cases where existing records might have old or new unit formats
            Map<String, UTXO_Asset__c> unitToExistingAsset = new Map<String, UTXO_Asset__c>();
            Map<String, List<UTXO_Asset__c>> duplicateTracker = new Map<String, List<UTXO_Asset__c>>();
            
            for (UTXO_Asset__c asset : existingAssets) {
                String currentUnit = asset.Unit__c;
                String compositeKey = currentUnit + ':' + asset.UTXO_Address__c;
                
                // Track duplicates for cleanup
                if (!duplicateTracker.containsKey(currentUnit)) {
                    duplicateTracker.put(currentUnit, new List<UTXO_Asset__c>());
                }
                duplicateTracker.get(currentUnit).add(asset);
                
                // Use the most recent record if duplicates exist
                if (!unitToExistingAsset.containsKey(compositeKey) || 
                    asset.CreatedDate > unitToExistingAsset.get(compositeKey).CreatedDate) {
                    unitToExistingAsset.put(compositeKey, asset);
                }
                
                // Also map the reverse lookup for old/new format compatibility
                // If existing record has "ADA", also map it to "lovelace" key for lookup
                if (currentUnit == 'ADA') {
                    String lovelaceKey = 'lovelace:' + asset.UTXO_Address__c;
                    if (!unitToExistingAsset.containsKey(lovelaceKey) || 
                        asset.CreatedDate > unitToExistingAsset.get(lovelaceKey).CreatedDate) {
                        unitToExistingAsset.put(lovelaceKey, asset);
                    }
                }
                // If existing record has "lovelace", also map it to "ADA" key for lookup  
                else if (currentUnit == 'lovelace') {
                    String adaKey = 'ADA:' + asset.UTXO_Address__c;
                    if (!unitToExistingAsset.containsKey(adaKey) || 
                        asset.CreatedDate > unitToExistingAsset.get(adaKey).CreatedDate) {
                        unitToExistingAsset.put(adaKey, asset);
                    }
                }
            }
            
            // Clean up duplicates - delete older duplicate records
            List<UTXO_Asset__c> duplicatesToDelete = new List<UTXO_Asset__c>();
            for (String unit : duplicateTracker.keySet()) {
                List<UTXO_Asset__c> unitAssets = duplicateTracker.get(unit);
                if (unitAssets.size() > 1) {
                    Logger.logInfo('[UTXOAssetController.syncAssets] 🧹 Found ' + unitAssets.size() + ' duplicate records for unit: ' + unit);
                    // Find the record with the latest CreatedDate to keep
                    UTXO_Asset__c newestRecord = unitAssets[0];
                    for (UTXO_Asset__c asset : unitAssets) {
                        if (asset.CreatedDate > newestRecord.CreatedDate) {
                            newestRecord = asset;
                        }
                    }
                    // Mark all other records for deletion
                    for (UTXO_Asset__c asset : unitAssets) {
                        if (asset.Id != newestRecord.Id) {
                            duplicatesToDelete.add(asset);
                            Logger.logInfo('[UTXOAssetController.syncAssets] 🗑️  Marking duplicate for deletion: ' + asset.Id);
                        }
                    }
                }
            }
            
            // Delete duplicate records
            if (!duplicatesToDelete.isEmpty()) {
                delete duplicatesToDelete;
                Logger.logInfo('[UTXOAssetController.syncAssets] ✅ Cleaned up ' + duplicatesToDelete.size() + ' duplicate records');
            }
            
            List<UTXO_Asset__c> assetsToInsert = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> assetsToUpdate = new List<UTXO_Asset__c>();
            
            for (String unit : unitToTotalAmount.keySet()) {
                Decimal totalAmount = unitToTotalAmount.get(unit);
                
                // Determine the display unit (what we'll store in Unit__c)
                String displayUnit = unit;
                String assetName = unit;
                
                if (unit == 'lovelace') {
                    displayUnit = 'ADA';
                    assetName = 'Cardano';
                } else if (unitToMetadata.containsKey(unit)) {
                    try {
                        Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                        if (metadata.containsKey('metadata')) {
                            Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                            if (innerMeta.containsKey('ticker')) {
                                displayUnit = String.valueOf(innerMeta.get('ticker'));
                                assetName = displayUnit;
                            }
                            if (innerMeta.containsKey('name')) {
                                assetName = String.valueOf(innerMeta.get('name'));
                            }
                        }
                    } catch (Exception e) {
                        Logger.logError('[UTXOAssetController.syncAssets] ❌ Error parsing metadata for display unit: ' + unit);
                    }
                }
                
                // Try to find existing asset with either old or new unit format
                String newCompositeKey = displayUnit + ':' + utxoAddress.Id;
                String oldCompositeKey = unit + ':' + utxoAddress.Id;  // For backward compatibility
                
                UTXO_Asset__c existingAsset = null;
                if (unitToExistingAsset.containsKey(newCompositeKey)) {
                    existingAsset = unitToExistingAsset.get(newCompositeKey);
                } else if (unitToExistingAsset.containsKey(oldCompositeKey)) {
                    existingAsset = unitToExistingAsset.get(oldCompositeKey);
                }
                
                if (existingAsset != null) {
                    // Update existing asset
                    Boolean needsUpdate = false;
                    
                    if (existingAsset.Amount__c != totalAmount) {
                        existingAsset.Amount__c = totalAmount;
                        needsUpdate = true;
                    }
                    
                    // Update unit to new format if it's in old format
                    if (existingAsset.Unit__c != displayUnit) {
                        existingAsset.Unit__c = displayUnit;
                        existingAsset.Name__c = assetName;
                        existingAsset.Asset_Name__c = displayUnit;
                        if (unit == 'lovelace') {
                            existingAsset.Decimals__c = 6;
                        } else {
                            // For non-ADA assets, populate metadata fields if they're missing
                            if (unitToMetadata.containsKey(unit)) {
                                try {
                                    Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                                    
                                    // Set Policy ID if missing
                                    if ((existingAsset.Policy_ID__c == null || existingAsset.Policy_ID__c == '') && 
                                        metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                                        existingAsset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                                    }
                                    
                                    // Set Fingerprint if missing
                                    if ((existingAsset.Fingerprint__c == null || existingAsset.Fingerprint__c == '') && 
                                        metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                                        existingAsset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                                    }
                                    
                                    // Set Decimals if missing
                                    if (existingAsset.Decimals__c == null && metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                                        Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                                        if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                                            Object decimalsObj = innerMeta.get('decimals');
                                            if (decimalsObj instanceof Integer) {
                                                existingAsset.Decimals__c = (Integer) decimalsObj;
                                            } else if (decimalsObj instanceof Decimal) {
                                                existingAsset.Decimals__c = ((Decimal) decimalsObj).intValue();
                                            } else {
                                                existingAsset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                                            }
                                        }
                                    }
                                } catch (Exception e) {
                                    Logger.logError('[UTXOAssetController] ❌ Error updating metadata fields for existing asset: ' + unit + ' - ' + e.getMessage());
                                }
                            }
                        }
                        needsUpdate = true;
                    } else {
                        // Even if unit format is correct, check if metadata fields need to be populated
                        if (unit != 'lovelace' && unitToMetadata.containsKey(unit)) {
                            try {
                                Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                                
                                // Check and set Policy ID if missing
                                if ((existingAsset.Policy_ID__c == null || existingAsset.Policy_ID__c == '') && 
                                    metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                                    existingAsset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                                    needsUpdate = true;
                                }
                                
                                // Check and set Fingerprint if missing
                                if ((existingAsset.Fingerprint__c == null || existingAsset.Fingerprint__c == '') && 
                                    metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                                    existingAsset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                                    needsUpdate = true;
                                }
                                
                                // Check and set Decimals if missing
                                if (existingAsset.Decimals__c == null && metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                                    if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                                        Object decimalsObj = innerMeta.get('decimals');
                                        if (decimalsObj instanceof Integer) {
                                            existingAsset.Decimals__c = (Integer) decimalsObj;
                                        } else if (decimalsObj instanceof Decimal) {
                                            existingAsset.Decimals__c = ((Decimal) decimalsObj).intValue();
                                        } else {
                                            existingAsset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                                        }
                                        needsUpdate = true;
                                    }
                                }
                            } catch (Exception e) {
                                Logger.logError('[UTXOAssetController] ❌ Error checking metadata fields for existing asset: ' + unit + ' - ' + e.getMessage());
                            }
                        }
                    }
                    
                    if (needsUpdate) {
                        assetsToUpdate.add(existingAsset);
                    }
                } else {
                    // Create new
                    UTXO_Asset__c newAsset = new UTXO_Asset__c(
                        UTXO_Address__c = utxoAddress.Id,
                        Unit__c = displayUnit,
                        Amount__c = totalAmount,
                        Name__c = assetName,
                        Asset_Name__c = displayUnit
                    );
                    
                    // Set additional values based on asset type
                    if (unit == 'lovelace') {
                        newAsset.Decimals__c = 6;
                    } else {
                        // For non-ADA assets, populate metadata fields
                        if (unitToMetadata.containsKey(unit)) {
                            try {
                                Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                                
                                // Set Policy ID
                                if (metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                                    newAsset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                                }
                                
                                // Set Fingerprint
                                if (metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                                    newAsset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                                }
                                
                                // Set Decimals from metadata
                                if (metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                                    if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                                        Object decimalsObj = innerMeta.get('decimals');
                                        if (decimalsObj instanceof Integer) {
                                            newAsset.Decimals__c = (Integer) decimalsObj;
                                        } else if (decimalsObj instanceof Decimal) {
                                            newAsset.Decimals__c = ((Decimal) decimalsObj).intValue();
                                        } else {
                                            newAsset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                                        }
                                    }
                                }
                                
                                Logger.logInfo('[UTXOAssetController] 📋 Set metadata fields for ' + displayUnit + 
                                    ' - Policy ID: ' + newAsset.Policy_ID__c + 
                                    ', Fingerprint: ' + newAsset.Fingerprint__c + 
                                    ', Decimals: ' + newAsset.Decimals__c);
                                    
                            } catch (Exception e) {
                                Logger.logError('[UTXOAssetController] ❌ Error setting metadata fields for unit: ' + unit + ' - ' + e.getMessage());
                            }
                        }
                    }
                    
                    assetsToInsert.add(newAsset);
                }
            }
            
            // Perform DML operations
            Integer insertedCount = 0;
            Integer updatedCount = 0;
            
            if (!assetsToInsert.isEmpty()) {
                insert assetsToInsert;
                insertedCount = assetsToInsert.size();
            }
            
            if (!assetsToUpdate.isEmpty()) {
                update assetsToUpdate;
                updatedCount = assetsToUpdate.size();
            }
            
            Long processingTime = System.now().getTime() - startTime;
            
            Logger.logInfo('[UTXOAssetController.syncAssets] ✅ Completed - Inserted: ' + insertedCount + 
                         ', Updated: ' + updatedCount + ', Time: ' + processingTime + 'ms');
            
            return new Map<String, Object>{
                'success' => true,
                'statistics' => new Map<String, Object>{
                    'assetsInserted' => insertedCount,
                    'assetsUpdated' => updatedCount,
                    'processingTimeMs' => processingTime
                },
                'assets' => utxoList,
                'message' => 'Assets synchronized successfully'
            };
            
        } catch (Exception e) {
            Logger.logError('[UTXOAssetController.syncAssets] ❌ Error: ' + e.getMessage());
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage(),
                'error' => e.getTypeName()
            };
        }
    }
    
    /**
     * Synchronizes transactions only for a UTXO address
     * @param utxoAddressId The UTXO Address ID to sync transactions for
     * @return Map with transaction data and statistics
     */
    @AuraEnabled
    public static Map<String, Object> syncTransactions(Id utxoAddressId) {
        try {
            Logger.logInfo('[UTXOAssetController.syncTransactions] 🚀 Starting transaction sync for address ID: ' + utxoAddressId);
            Long startTime = System.now().getTime();
            
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address ID cannot be null');
            }
            
            // Get the UTXO Address record
            UTXO_Address__c utxoAddress = [
                SELECT Id, Address__c, Wallet__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];
            
            if (utxoAddress == null) {
                throw new AuraHandledException('UTXO Address not found');
            }
            
            Logger.logInfo('[UTXOAssetController.syncTransactions] 📍 Processing address: ' + utxoAddress.Address__c);
            
            // Step 1: Get transactions from Blockfrost
            String transactionsJson = BlockfrostService.getAddressTransactions(utxoAddress.Address__c);
            List<Object> transactionList = (List<Object>) JSON.deserializeUntyped(transactionsJson);
            
            Logger.logInfo('[UTXOAssetController.syncTransactions] 📊 Found ' + transactionList.size() + ' transactions');
            
            if (transactionList.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'statistics' => new Map<String, Object>{
                        'transactionsInserted' => 0,
                        'transactionsUpdated' => 0,
                        'processingTimeMs' => System.now().getTime() - startTime
                    },
                    'transactions' => new List<Object>(),
                    'message' => 'No transactions found'
                };
            }
            
            // Step 2: Get existing transactions to avoid duplicates
            Map<String, Inbound_Transaction__c> existingTransactions = new Map<String, Inbound_Transaction__c>();
            for (Inbound_Transaction__c existing : [
                SELECT Id, Transaction_Hash__c, Block_Height__c, Block_Time__c
                FROM Inbound_Transaction__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ]) {
                existingTransactions.put(existing.Transaction_Hash__c, existing);
            }
            
            // Step 3: Process transactions
            List<Inbound_Transaction__c> transactionsToInsert = new List<Inbound_Transaction__c>();
            List<Inbound_Transaction__c> transactionsToUpdate = new List<Inbound_Transaction__c>();
            
            for (Object txObj : transactionList) {
                Map<String, Object> tx = (Map<String, Object>) txObj;
                String txHash = String.valueOf(tx.get('tx_hash'));
                
                if (existingTransactions.containsKey(txHash)) {
                    // Update existing if needed
                    Inbound_Transaction__c existing = existingTransactions.get(txHash);
                    Boolean needsUpdate = false;
                    
                    if (tx.get('block_height') != null) {
                        Integer blockHeight = Integer.valueOf(String.valueOf(tx.get('block_height')));
                        if (existing.Block_Height__c != blockHeight) {
                            existing.Block_Height__c = blockHeight;
                            needsUpdate = true;
                        }
                    }
                    
                    if (tx.get('block_time') != null) {
                        Integer blockTime = Integer.valueOf(String.valueOf(tx.get('block_time')));
                        if (existing.Block_Time__c != blockTime) {
                            existing.Block_Time__c = blockTime;
                            needsUpdate = true;
                        }
                    }
                    
                    if (needsUpdate) {
                        transactionsToUpdate.add(existing);
                    }
                } else {
                    // Create new transaction
                    Inbound_Transaction__c newTransaction = new Inbound_Transaction__c(
                        UTXO_Address__c = utxoAddress.Id,
                        Transaction_Hash__c = txHash
                    );
                    
                    if (tx.get('tx_index') != null) {
                        newTransaction.Transaction_Index__c = Integer.valueOf(String.valueOf(tx.get('tx_index')));
                    }
                    
                    if (tx.get('block_height') != null) {
                        newTransaction.Block_Height__c = Integer.valueOf(String.valueOf(tx.get('block_height')));
                    }
                    
                    if (tx.get('block_time') != null) {
                        newTransaction.Block_Time__c = Integer.valueOf(String.valueOf(tx.get('block_time')));
                    }
                    
                    transactionsToInsert.add(newTransaction);
                }
            }
            
            // Perform DML operations
            Integer insertedCount = 0;
            Integer updatedCount = 0;
            
            if (!transactionsToInsert.isEmpty()) {
                insert transactionsToInsert;
                insertedCount = transactionsToInsert.size();
            }
            
            if (!transactionsToUpdate.isEmpty()) {
                update transactionsToUpdate;
                updatedCount = transactionsToUpdate.size();
            }
            
            Long processingTime = System.now().getTime() - startTime;
            
            Logger.logInfo('[UTXOAssetController.syncTransactions] ✅ Completed - Inserted: ' + insertedCount + 
                         ', Updated: ' + updatedCount + ', Time: ' + processingTime + 'ms');
            
            return new Map<String, Object>{
                'success' => true,
                'statistics' => new Map<String, Object>{
                    'transactionsInserted' => insertedCount,
                    'transactionsUpdated' => updatedCount,
                    'processingTimeMs' => processingTime
                },
                'transactions' => transactionList,
                'message' => 'Transactions synchronized successfully'
            };
            
        } catch (Exception e) {
            Logger.logError('[UTXOAssetController.syncTransactions] ❌ Error: ' + e.getMessage());
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage(),
                'error' => e.getTypeName()
            };
        }
    }
    
    /**
     * Synchronizes both assets and transactions for a UTXO address
     * @param utxoAddressId The UTXO Address ID to sync
     * @return Map with combined results
     */
    @AuraEnabled
    public static Map<String, Object> syncAssetsAndTransactions(Id utxoAddressId) {
        try {
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 🚀 Starting combined sync for address ID: ' + utxoAddressId);
            Long totalStartTime = System.now().getTime();
            
            if (utxoAddressId == null) {
                throw new AuraHandledException('UTXO Address ID cannot be null');
            }
            
            // Get the UTXO Address record
            UTXO_Address__c utxoAddress = [
                SELECT Id, Address__c, Wallet__c
                FROM UTXO_Address__c
                WHERE Id = :utxoAddressId
                LIMIT 1
            ];
            
            if (utxoAddress == null) {
                throw new AuraHandledException('UTXO Address not found');
            }
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📍 Processing address: ' + utxoAddress.Address__c);
            
            // PHASE 1: ALL CALLOUTS FIRST (to avoid callout-after-DML issues)
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📡 Phase 1: Making all API callouts');
            
            // Step 1: Get UTXOs from Blockfrost
            String utxoJson = BlockfrostService.getAddressUtxos(utxoAddress.Address__c);
            List<Object> utxoList = (List<Object>) JSON.deserializeUntyped(utxoJson);
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📦 Found ' + utxoList.size() + ' UTXOs');
            
            // Step 2: Get transactions from Blockfrost
            String transactionsJson = BlockfrostService.getAddressTransactions(utxoAddress.Address__c);
            List<Object> transactionList = (List<Object>) JSON.deserializeUntyped(transactionsJson);
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Found ' + transactionList.size() + ' transactions');
            
            // Step 3: Collect all unique asset units and fetch metadata
            Set<String> allUnits = new Set<String>();
            Map<String, String> unitToMetadata = new Map<String, String>();
            
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                List<Object> amounts = (List<Object>) utxo.get('amount');
                if (amounts != null) {
                    for (Object amtObj : amounts) {
                        Map<String, Object> amt = (Map<String, Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        allUnits.add(unit);
                    }
                }
            }
            
            // Fetch metadata for all non-lovelace units
            for (String unit : allUnits) {
                if (unit != 'lovelace') {
                    try {
                        String metadata = BlockfrostService.getAssetMetadata(unit);
                        if (metadata != null && metadata != '{}') {
                            unitToMetadata.put(unit, metadata);
                        }
                    } catch (Exception e) {
                        Logger.logError('[UTXOAssetController.syncAssetsAndTransactions] ❌ Failed to fetch metadata for unit: ' + unit + ' - ' + e.getMessage());
                    }
                }
            }
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Phase 1 complete - All callouts finished');
            
            // PHASE 2: PROCESS AND SAVE DATA (all DML operations)
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 💾 Phase 2: Processing and saving data');
            
            // Process assets
            Map<String, Decimal> unitToTotalAmount = new Map<String, Decimal>();
            
            for (Object utxoObj : utxoList) {
                Map<String, Object> utxo = (Map<String, Object>) utxoObj;
                List<Object> amounts = (List<Object>) utxo.get('amount');
                if (amounts != null) {
                    for (Object amtObj : amounts) {
                        Map<String, Object> amt = (Map<String, Object>) amtObj;
                        String unit = String.valueOf(amt.get('unit'));
                        Decimal quantity = Decimal.valueOf(String.valueOf(amt.get('quantity')));
                        
                        if (!unitToTotalAmount.containsKey(unit)) {
                            unitToTotalAmount.put(unit, 0);
                        }
                        unitToTotalAmount.put(unit, unitToTotalAmount.get(unit) + quantity);
                    }
                }
            }
            
            // Get existing assets and transactions
            List<UTXO_Asset__c> existingAssets = [
                SELECT Id, Unit__c, Amount__c, UTXO_Address__c
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ];
            
            Map<String, Inbound_Transaction__c> existingTransactions = new Map<String, Inbound_Transaction__c>();
            for (Inbound_Transaction__c existing : [
                SELECT Id, Transaction_Hash__c, Block_Height__c, Block_Time__c
                FROM Inbound_Transaction__c
                WHERE UTXO_Address__c = :utxoAddress.Id
            ]) {
                existingTransactions.put(existing.Transaction_Hash__c, existing);
            }
            
            // Prepare asset operations - Create a comprehensive lookup map for existing assets
            // We need to handle cases where existing records might have old or new unit formats
            Map<String, UTXO_Asset__c> unitToExistingAsset = new Map<String, UTXO_Asset__c>();
            for (UTXO_Asset__c asset : existingAssets) {
                String currentUnit = asset.Unit__c;
                String compositeKey = currentUnit + ':' + asset.UTXO_Address__c;
                unitToExistingAsset.put(compositeKey, asset);
                
                // Also map the reverse lookup for old/new format compatibility
                // If existing record has "ADA", also map it to "lovelace" key for lookup
                if (currentUnit == 'ADA') {
                    String lovelaceKey = 'lovelace:' + asset.UTXO_Address__c;
                    unitToExistingAsset.put(lovelaceKey, asset);
                }
                // If existing record has "lovelace", also map it to "ADA" key for lookup  
                else if (currentUnit == 'lovelace') {
                    String adaKey = 'ADA:' + asset.UTXO_Address__c;
                    unitToExistingAsset.put(adaKey, asset);
                }
            }
            
            List<UTXO_Asset__c> assetsToInsert = new List<UTXO_Asset__c>();
            List<UTXO_Asset__c> assetsToUpdate = new List<UTXO_Asset__c>();
            
            for (String unit : unitToTotalAmount.keySet()) {
                Decimal totalAmount = unitToTotalAmount.get(unit);
                
                // Determine the display unit (what we'll store in Unit__c)
                String displayUnit = unit;
                String assetName = unit;
                
                if (unit == 'lovelace') {
                    displayUnit = 'ADA';
                    assetName = 'Cardano';
                } else if (unitToMetadata.containsKey(unit)) {
                    try {
                        Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                        if (metadata.containsKey('metadata')) {
                            Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                            if (innerMeta.containsKey('ticker')) {
                                displayUnit = String.valueOf(innerMeta.get('ticker'));
                                assetName = displayUnit;
                            }
                            if (innerMeta.containsKey('name')) {
                                assetName = String.valueOf(innerMeta.get('name'));
                            }
                        }
                    } catch (Exception e) {
                        Logger.logError('[UTXOAssetController.syncAssetsAndTransactions] ❌ Error parsing metadata for display unit: ' + unit);
                    }
                }
                
                // Try to find existing asset with either old or new unit format
                String newCompositeKey = displayUnit + ':' + utxoAddress.Id;
                String oldCompositeKey = unit + ':' + utxoAddress.Id;  // For backward compatibility
                
                UTXO_Asset__c existingAsset = null;
                if (unitToExistingAsset.containsKey(newCompositeKey)) {
                    existingAsset = unitToExistingAsset.get(newCompositeKey);
                } else if (unitToExistingAsset.containsKey(oldCompositeKey)) {
                    existingAsset = unitToExistingAsset.get(oldCompositeKey);
                }
                
                if (existingAsset != null) {
                    // Update existing asset
                    Boolean needsUpdate = false;
                    
                    if (existingAsset.Amount__c != totalAmount) {
                        existingAsset.Amount__c = totalAmount;
                        needsUpdate = true;
                    }
                    
                    // Update unit to new format if it's in old format
                    if (existingAsset.Unit__c != displayUnit) {
                        existingAsset.Unit__c = displayUnit;
                        existingAsset.Name__c = assetName;
                        existingAsset.Asset_Name__c = displayUnit;
                        if (unit == 'lovelace') {
                            existingAsset.Decimals__c = 6;
                        } else {
                            // For non-ADA assets, populate metadata fields if they're missing
                            if (unitToMetadata.containsKey(unit)) {
                                try {
                                    Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                                    
                                    // Set Policy ID if missing
                                    if ((existingAsset.Policy_ID__c == null || existingAsset.Policy_ID__c == '') && 
                                        metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                                        existingAsset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                                    }
                                    
                                    // Set Fingerprint if missing
                                    if ((existingAsset.Fingerprint__c == null || existingAsset.Fingerprint__c == '') && 
                                        metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                                        existingAsset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                                    }
                                    
                                    // Set Decimals if missing
                                    if (existingAsset.Decimals__c == null && metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                                        Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                                        if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                                            Object decimalsObj = innerMeta.get('decimals');
                                            if (decimalsObj instanceof Integer) {
                                                existingAsset.Decimals__c = (Integer) decimalsObj;
                                            } else if (decimalsObj instanceof Decimal) {
                                                existingAsset.Decimals__c = ((Decimal) decimalsObj).intValue();
                                            } else {
                                                existingAsset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                                            }
                                        }
                                    }
                                } catch (Exception e) {
                                    Logger.logError('[UTXOAssetController] ❌ Error updating metadata fields for existing asset: ' + unit + ' - ' + e.getMessage());
                                }
                            }
                        }
                        needsUpdate = true;
                    } else {
                        // Even if unit format is correct, check if metadata fields need to be populated
                        if (unit != 'lovelace' && unitToMetadata.containsKey(unit)) {
                            try {
                                Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                                
                                // Check and set Policy ID if missing
                                if ((existingAsset.Policy_ID__c == null || existingAsset.Policy_ID__c == '') && 
                                    metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                                    existingAsset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                                    needsUpdate = true;
                                }
                                
                                // Check and set Fingerprint if missing
                                if ((existingAsset.Fingerprint__c == null || existingAsset.Fingerprint__c == '') && 
                                    metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                                    existingAsset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                                    needsUpdate = true;
                                }
                                
                                // Check and set Decimals if missing
                                if (existingAsset.Decimals__c == null && metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                                    if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                                        Object decimalsObj = innerMeta.get('decimals');
                                        if (decimalsObj instanceof Integer) {
                                            existingAsset.Decimals__c = (Integer) decimalsObj;
                                        } else if (decimalsObj instanceof Decimal) {
                                            existingAsset.Decimals__c = ((Decimal) decimalsObj).intValue();
                                        } else {
                                            existingAsset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                                        }
                                        needsUpdate = true;
                                    }
                                }
                            } catch (Exception e) {
                                Logger.logError('[UTXOAssetController] ❌ Error checking metadata fields for existing asset: ' + unit + ' - ' + e.getMessage());
                            }
                        }
                    }
                    
                    if (needsUpdate) {
                        assetsToUpdate.add(existingAsset);
                    }
                } else {
                    // Create new
                    UTXO_Asset__c newAsset = new UTXO_Asset__c(
                        UTXO_Address__c = utxoAddress.Id,
                        Unit__c = displayUnit,
                        Amount__c = totalAmount,
                        Name__c = assetName,
                        Asset_Name__c = displayUnit
                    );
                    
                    // Set additional values based on asset type
                    if (unit == 'lovelace') {
                        newAsset.Decimals__c = 6;
                    } else {
                        // For non-ADA assets, populate metadata fields
                        if (unitToMetadata.containsKey(unit)) {
                            try {
                                Map<String, Object> metadata = (Map<String, Object>) JSON.deserializeUntyped(unitToMetadata.get(unit));
                                
                                // Set Policy ID
                                if (metadata.containsKey('policy_id') && metadata.get('policy_id') != null) {
                                    newAsset.Policy_ID__c = String.valueOf(metadata.get('policy_id'));
                                }
                                
                                // Set Fingerprint
                                if (metadata.containsKey('fingerprint') && metadata.get('fingerprint') != null) {
                                    newAsset.Fingerprint__c = String.valueOf(metadata.get('fingerprint'));
                                }
                                
                                // Set Decimals from metadata
                                if (metadata.containsKey('metadata') && metadata.get('metadata') != null) {
                                    Map<String, Object> innerMeta = (Map<String, Object>) metadata.get('metadata');
                                    if (innerMeta.containsKey('decimals') && innerMeta.get('decimals') != null) {
                                        Object decimalsObj = innerMeta.get('decimals');
                                        if (decimalsObj instanceof Integer) {
                                            newAsset.Decimals__c = (Integer) decimalsObj;
                                        } else if (decimalsObj instanceof Decimal) {
                                            newAsset.Decimals__c = ((Decimal) decimalsObj).intValue();
                                        } else {
                                            newAsset.Decimals__c = Integer.valueOf(String.valueOf(decimalsObj));
                                        }
                                    }
                                }
                                
                                Logger.logInfo('[UTXOAssetController] 📋 Set metadata fields for ' + displayUnit + 
                                    ' - Policy ID: ' + newAsset.Policy_ID__c + 
                                    ', Fingerprint: ' + newAsset.Fingerprint__c + 
                                    ', Decimals: ' + newAsset.Decimals__c);
                                    
                            } catch (Exception e) {
                                Logger.logError('[UTXOAssetController] ❌ Error setting metadata fields for unit: ' + unit + ' - ' + e.getMessage());
                            }
                        }
                    }
                    
                    assetsToInsert.add(newAsset);
                }
            }
            
            // Prepare transaction operations
            List<Inbound_Transaction__c> transactionsToInsert = new List<Inbound_Transaction__c>();
            List<Inbound_Transaction__c> transactionsToUpdate = new List<Inbound_Transaction__c>();
            
            for (Object txObj : transactionList) {
                Map<String, Object> tx = (Map<String, Object>) txObj;
                String txHash = String.valueOf(tx.get('tx_hash'));
                
                if (existingTransactions.containsKey(txHash)) {
                    // Update existing if needed
                    Inbound_Transaction__c existing = existingTransactions.get(txHash);
                    Boolean needsUpdate = false;
                    
                    if (tx.get('block_height') != null) {
                        Integer blockHeight = Integer.valueOf(String.valueOf(tx.get('block_height')));
                        if (existing.Block_Height__c != blockHeight) {
                            existing.Block_Height__c = blockHeight;
                            needsUpdate = true;
                        }
                    }
                    
                    if (tx.get('block_time') != null) {
                        Integer blockTime = Integer.valueOf(String.valueOf(tx.get('block_time')));
                        if (existing.Block_Time__c != blockTime) {
                            existing.Block_Time__c = blockTime;
                            needsUpdate = true;
                        }
                    }
                    
                    if (needsUpdate) {
                        transactionsToUpdate.add(existing);
                    }
                } else {
                    // Create new transaction
                    Inbound_Transaction__c newTransaction = new Inbound_Transaction__c(
                        UTXO_Address__c = utxoAddress.Id,
                        Transaction_Hash__c = txHash
                    );
                    
                    if (tx.get('tx_index') != null) {
                        newTransaction.Transaction_Index__c = Integer.valueOf(String.valueOf(tx.get('tx_index')));
                    }
                    
                    if (tx.get('block_height') != null) {
                        newTransaction.Block_Height__c = Integer.valueOf(String.valueOf(tx.get('block_height')));
                    }
                    
                    if (tx.get('block_time') != null) {
                        newTransaction.Block_Time__c = Integer.valueOf(String.valueOf(tx.get('block_time')));
                    }
                    
                    transactionsToInsert.add(newTransaction);
                }
            }
            
            // Perform all DML operations
            Integer assetsInserted = 0;
            Integer assetsUpdated = 0;
            Integer transactionsInserted = 0;
            Integer transactionsUpdated = 0;
            
            if (!assetsToInsert.isEmpty()) {
                insert assetsToInsert;
                assetsInserted = assetsToInsert.size();
            }
            
            if (!assetsToUpdate.isEmpty()) {
                update assetsToUpdate;
                assetsUpdated = assetsToUpdate.size();
            }
            
            if (!transactionsToInsert.isEmpty()) {
                insert transactionsToInsert;
                transactionsInserted = transactionsToInsert.size();
            }
            
            if (!transactionsToUpdate.isEmpty()) {
                update transactionsToUpdate;
                transactionsUpdated = transactionsToUpdate.size();
            }
            
            Long totalProcessingTime = System.now().getTime() - totalStartTime;
            
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] ✅ Combined sync completed in ' + totalProcessingTime + 'ms');
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Assets - Inserted: ' + assetsInserted + ', Updated: ' + assetsUpdated);
            Logger.logInfo('[UTXOAssetController.syncAssetsAndTransactions] 📊 Transactions - Inserted: ' + transactionsInserted + ', Updated: ' + transactionsUpdated);
            
            return new Map<String, Object>{
                'success' => true,
                'assets' => utxoList,
                'transactions' => transactionList,
                'statistics' => new Map<String, Object>{
                    'assetsInserted' => assetsInserted,
                    'assetsUpdated' => assetsUpdated,
                    'transactionsInserted' => transactionsInserted,
                    'transactionsUpdated' => transactionsUpdated,
                    'totalProcessingTimeMs' => totalProcessingTime
                },
                'message' => 'Assets and transactions synchronized successfully'
            };
            
        } catch (Exception e) {
            Logger.logError('[UTXOAssetController.syncAssetsAndTransactions] ❌ Error: ' + e.getMessage());
            return new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage(),
                'error' => e.getTypeName()
            };
        }
    }

    /**
     * Get asset summary for a wallet (all assets across all UTXO addresses)
     * @param walletId The wallet ID to get assets for
     * @return Map with asset summary data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getWalletAssetSummary(Id walletId) {
        try {
            Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 🚀 Getting asset summary for wallet: ' + walletId);
            
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get all UTXO addresses for this wallet
            List<UTXO_Address__c> utxoAddresses = [
                SELECT Id
                FROM UTXO_Address__c
                WHERE Wallet__c = :walletId
            ];
            
            if (utxoAddresses.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'adaBalance' => 0,
                    'tokens' => new List<Object>(),
                    'totalAssets' => 0,
                    'message' => 'No UTXO addresses found for this wallet'
                };
            }
            
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) {
                utxoAddressIds.add(addr.Id);
            }
            
            // Get all assets for these addresses, aggregated by Unit
            AggregateResult[] assetAggregates = [
                SELECT Unit__c, SUM(Amount__c) totalAmount, SUM(Value__c) totalValue, 
                       MAX(Name__c) assetName, MAX(Asset_Name__c) displayName, 
                       MAX(Decimals__c) decimals, MAX(Policy_ID__c) policyId,
                       MAX(Fingerprint__c) fingerprint
                FROM UTXO_Asset__c
                WHERE UTXO_Address__c IN :utxoAddressIds
                AND Amount__c > 0
                GROUP BY Unit__c
                ORDER BY Unit__c
            ];
            
            Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 📊 Found ' + assetAggregates.size() + ' aggregated assets');
            
            Decimal adaBalance = 0;
            List<Map<String, Object>> tokens = new List<Map<String, Object>>();
            
            for (AggregateResult ar : assetAggregates) {
                String unit = String.valueOf(ar.get('Unit__c'));
                Decimal totalAmount = (Decimal) ar.get('totalAmount');
                Decimal totalValue = (Decimal) ar.get('totalValue');
                String assetName = String.valueOf(ar.get('assetName'));
                String displayName = String.valueOf(ar.get('displayName'));
                Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
                String policyId = String.valueOf(ar.get('policyId'));
                String fingerprint = String.valueOf(ar.get('fingerprint'));
                
                if (unit == 'ADA') {
                    // For ADA, use the Value__c field which converts lovelace to ADA
                    adaBalance = totalValue != null ? totalValue : 0;
                    Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 💰 ADA Balance: ' + adaBalance + ' (from ' + totalAmount + ' lovelace)');
                } else {
                    // For tokens, add to tokens list
                    Map<String, Object> tokenInfo = new Map<String, Object>{
                        'unit' => unit,
                        'name' => assetName != null ? assetName : unit,
                        'symbol' => displayName != null ? displayName : unit,
                        'amount' => totalValue != null ? totalValue : totalAmount, // Use Value__c for formatted amount
                        'rawAmount' => totalAmount, // Keep raw amount for reference
                        'decimals' => decimals,
                        'policyId' => policyId != 'null' ? policyId : null,
                        'fingerprint' => fingerprint != 'null' ? fingerprint : null,
                        'icon' => 'utility:apps' // Default icon
                    };
                    tokens.add(tokenInfo);
                    
                    Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] 🪙 Token: ' + unit + 
                                 ' - Amount: ' + totalValue + ' (from ' + totalAmount + ' raw)');
                }
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'adaBalance' => adaBalance,
                'tokens' => tokens,
                'totalAssets' => assetAggregates.size(),
                'message' => 'Asset summary retrieved successfully'
            };
            
            Logger.logInfo('[UTXOAssetController.getWalletAssetSummary] ✅ Summary complete - ADA: ' + adaBalance + ', Tokens: ' + tokens.size());
            return result;
            
        } catch (Exception e) {
            Logger.logError('[UTXOAssetController.getWalletAssetSummary] ❌ Error: ' + e.getMessage());
            throw new AuraHandledException('Failed to get wallet asset summary: ' + e.getMessage());
        }
    }
} 