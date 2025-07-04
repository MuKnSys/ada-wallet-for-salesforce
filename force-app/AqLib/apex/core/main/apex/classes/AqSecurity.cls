/*
 * Copyright (c) 2022, Aquiva Labs LLC. All rights reserved.
 * 
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 * 
 * - Redistributions of source code must retain the above copyright notice, 
 *     this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *     this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * - Neither the name of the Aquiva Labs LLC nor the names of its contributors
 *     may be used to endorse or promote products derived from this software without
 *     specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

/**
 * @description Utilities for object level security checks
 * @group apex/core
 */
public with sharing class AqSecurity {

    /**
     * Check accessible
     */
    public static void checkAccessPermissions (SObject record) {
        checkAccessPermissions(new List<SObject> {record});
    }

    /**
     * Check accessible
     */
    public static void checkAccessPermissions (List<SObject> records) {
        requirePermissions(System.AccessType.READABLE, records);
    }

    /**
     * Check createable
     */
    public static void checkCreatePermissions (SObject record) {
        checkCreatePermissions(new List<SObject> {record});
    }

    /**
     * Check createable
     */
    public static void checkCreatePermissions (List<SObject> records) {
        requirePermissions(System.AccessType.CREATABLE, records);
    }

    /**
     * Check updateable
     */
    public static void checkUpdatePermissions (SObject record) {
        checkUpdatePermissions(new List<SObject> {record});
    }

    /**
     * Check updateable
     */
    public static void checkUpdatePermissions (List<SObject> records) {
        requirePermissions(System.AccessType.UPDATABLE, records);
    }

    /**
     * Check upsertable
     */
    public static void checkUpsertPermissions (SObject record) {
        checkUpsertPermissions(new List<SObject> {record});
    }

    /**
     * Check upsertable
     */
    public static void checkUpsertPermissions (List<SObject> records) {
        requirePermissions(System.AccessType.UPSERTABLE, records);
    }

    /**
     * Check deleteable
     */
    public static void checkDeletePermissions (SObject record) {
        String sObjTypeName = String.valueOf(record.getSObjectType());
        AqSObject.requireDeletable(sObjTypeName);
    }

    /**
     * Check deleteable
     */
    public static void checkDeletePermissions (List<SObject> records) {
        Map<String, Set<String>> objectFields = Aq.getSObjectFieldNames(records);
        for (String objectName : objectFields.keySet()) {
            AqSObject.requireDeletable(objectName);
        }
    }

    /**
     * Check undeleteable
     */
    public static void checkUndeletePermissions (SObject record) {
        String sObjTypeName = String.valueOf(record.getSObjectType());
        AqSObject.requireDeletable(sObjTypeName);
    }

    /**
     * Check undeleteable
     */
    public static void checkUndeletePermissions (List<SObject> records) {
        Map<String, Set<String>> objectFields = Aq.getSObjectFieldNames(records);
        for (String objectName : objectFields.keySet()) {
            AqSObject.requireDeletable(objectName);
        }
    }

    private static void requirePermissions(System.AccessType accessCheckType, List<SObject> sourceRecords) {
        SObjectAccessDecision decision = Security.stripInaccessible(
            accessCheckType,
            sourceRecords,
            true
        );

        if (!decision.getModifiedIndexes().isEmpty() && !ignoreDMLStrippedFields(decision.getRemovedFields(), accessCheckType)) {
            String exceptionMessage = Label.Aq_M_InsufficientPrivilege;
            if (AqEnv.isDebugMode == true) {
                exceptionMessage += ' ' + getUnaccessibleFieldNames(accessCheckType, decision.getRemovedFields());
            }
            throw new Aq.PermissionException(exceptionMessage);
        }
    }

    private static String getUnaccessibleFieldNames(System.AccessType accessCheckType, Map<String,Set<String>> removedFields) {
        
        List<String> objectMessages = new List<String>();
        
        for (String objKey : removedFields.keySet()) {
            List<String> fields = new List<String>();
            for (String fKey : removedFields.get(objKey)) {
                if (!ignoreDMLStrippedField(objKey, fKey, accessCheckType)) {
                    fields.add(fKey);
                }
            }
            objectMessages.add(objKey + ' (' + String.join(fields, ',') + ')');
        }
        
        return 'required permission:' + accessCheckType.name() + '. \n' + String.join(objectMessages, '\n');
    }

    private static Boolean ignoreDMLStrippedFields(Map<String, Set<String>> removedFields, System.AccessType accessCheckType) {

        for (String sObjTypeName : removedFields.keySet()) {
            for (String fName : removedFields.get(sObjTypeName)) {
                if (!ignoreDMLStrippedField(sObjTypeName, fName, accessCheckType)) {
                    return false;
                }
            }
        }

        return true;
    }

    private static Boolean ignoreDMLStrippedField(String sObjTypeName, String fName, System.AccessType accessCheckType) {

        Set<System.AccessType> accessCheckToConsider = new Set<System.AccessType>{
            System.AccessType.CREATABLE,
            System.AccessType.UPDATABLE,
            System.AccessType.UPSERTABLE
        };

        return !(accessCheckToConsider.contains(accessCheckType) && AqField.isPermissionableForDML(sObjTypeName, fName));
    }
}
