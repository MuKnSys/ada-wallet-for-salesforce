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
 * @description Framework for DML operations.
 * 
 * @group apex/core
 */
public inherited sharing class AqDml {
    // --------------------------------------------------------------------------------
    // @start-group Insert
    // --------------------------------------------------------------------------------

    /**
     * Performs DML operation without CRUD check
     *
     * @param sObj  sObject for DML operation
     * @return      DML operation result
     */
    public static List<Database.SaveResult> insecureInsert(SObject sObj) {
        return insecureInsert(new List<SObject> { sObj }, true);
    }

    /**
     * Performs DML operation without CRUD check
     *
     * @param sObjects  sObjects for DML operation
     * @return          DML operations result
     */
    public static List<Database.SaveResult> insecureInsert(List<SObject> sObjects) {
        return insecureInsert(sObjects, true);
    }

    /**
     * Performs DML operation without CRUD check
     *
     * @param sObjects  sObjects for DML operation
     * @param allOrNone (Boolean): Skip all success operations in case at least one fail
     * @return          DML operations result
     */
    public static List<Database.SaveResult> insecureInsert(List<SObject> sObjects, Boolean allOrNone) {
        return Database.insert(sObjects, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Uses <<AqSecurity>> class to check CRUD permissions to
     * perform DML operation
     *
     * @param sObj  sObject for DML operation
     * @return      DML operation result
     */
    public static List<Database.SaveResult> secureInsert(SObject sObj) {
        return secureInsert(new List<SObject> {sObj}, true);
    }

    /**
     * Uses <<AqSecurity>> class to check CRUD permissions to
     * perform DML operation
     *
     * @param sObjects  sObjects for DML operation
     * @return          DML operations result
     */
    public static List<Database.SaveResult> secureInsert(List<SObject> sObjects) {
        return secureInsert(sObjects, true);
    }

    /**
     * Uses <<AqSecurity>> class to check CRUD permissions to
     * perform DML operation
     *
     * @param sObjects  sObjects for DML operation
     * @param allOrNone Skip all success operations in case at least one fail
     * @return          DML operations result
     */
    public static List<Database.SaveResult> secureInsert(List<SObject> sObjects, Boolean allOrNone) {
        return Database.insert(sObjects, allOrNone, AccessLevel.USER_MODE);
    }

    /**
     * Uses <<AqSecurity>> class to check CRUD permissions to
     * perform DML operation and wrap result in <<AqResult>>
     *
     * @param sObjects  sObjects for DML operation
     * @param allOrNone (Boolean): Skip all success operations in case at least one fail
     * @return          DML results wrapped in AqResult
     */
    public static List<AqResult> secureInsertWrapped(List<SObject> sObjects, Boolean allOrNone) {
        List<AqResult> results = new List<AqResult>();

        List<Database.SaveResult> insertRes = secureInsert(sObjects, allOrNone);
        for (Integer i = 0; i < sObjects.size(); i++) {
            results.add(
                new AqResultBuilder()
                    .setSaveResult(insertRes[i], sObjects[i].getSObjectType())
                    .createAqResult()
            );
        }

        return results;
    }
    // @end-group

    // --------------------------------------------------------------------------------
    // @start-group Update
    // --------------------------------------------------------------------------------
    /**
     * @description updates *obj* record without CRUD check
     * Insecure methods of the framework might be used for operations that
     * need to be executed in a system context without CRUD/FLS enforcement
     * @example
     * AqDml.insecureUpdate(obj);
     */
    public static List<Database.SaveResult> insecureUpdate(SObject sObj) {
        return insecureUpdate(new List<SObject> { sObj }, true);
    }

    public static List<Database.SaveResult> insecureUpdate(List<SObject> sObjects) {
        return insecureUpdate(sObjects, true);
    }

    public static List<Database.SaveResult> insecureUpdate(List<SObject> sObjects, Boolean allOrNone) {
        return Database.update(sObjects, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    public static List<Database.SaveResult> secureUpdate(SObject sObj) {
        return secureUpdate(new List<SObject> {sObj}, true);
    }

    public static List<Database.SaveResult> secureUpdate(List<SObject> sObjects) {
        return secureUpdate(sObjects, true);
    }

    public static List<Database.SaveResult> secureUpdate(List<SObject> sObjects, Boolean allOrNone) {
        return Database.update(sObjects, allOrNone, AccessLevel.USER_MODE);
    }

    public static List<AqResult> secureUpdateWrapped(List<SObject> sObjects, Boolean allOrNone) {
        List<AqResult> results = new List<AqResult>();

        List<Database.SaveResult> updateRes = secureUpdate(sObjects, allOrNone);
        for (Integer i = 0; i < sObjects.size(); i++) {
            results.add(
                new AqResultBuilder()
                    .setSaveResult(updateRes[i], sObjects[i].getSObjectType())
                    .createAqResult()
            );
        }

        return results;
    }
    // @end-group

    // --------------------------------------------------------------------------------
    // @start-group Upsert
    // --------------------------------------------------------------------------------
    public static List<Database.UpsertResult> insecureUpsert(SObject sObj, SObjectField field) {
        return insecureUpsert(new List<SObject> {sObj}, field, true);
    }

    public static List<Database.UpsertResult> insecureUpsert(List<SObject> sObjects, SObjectField field) {
        return insecureUpsert(sObjects, field, true);
    }

    public static List<Database.UpsertResult> insecureUpsert(List<SObject> sObjects, SObjectField field, Boolean allOrNone) {
        return Database.upsert(sObjects, field, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    public static List<Database.UpsertResult> secureUpsert(SObject sObj) {
        return secureUpsert(new List<SObject> { sObj }, null, true);
    }

    public static List<Database.UpsertResult> secureUpsert(List<SObject> sObjects) {
        return secureUpsert(sObjects, null, true);
    }

    public static List<Database.UpsertResult> secureUpsert(List<SObject> sObjects, SObjectField field, Boolean allOrNone) {
        if (field != null) {
            return Database.upsert(sObjects, field, allOrNone, AccessLevel.USER_MODE);
        }
        return Database.upsert(sObjects, allOrNone, AccessLevel.USER_MODE);
    }

    /**
     * @description upserts records with *allOrNone* flag, wrap DML results in *AqResult*
     * @param sObjects
     * @param field
     * @param allOrNone
     *
     * @return AqResult
     * @example
    *  List<AqResult> results = AqDml.secureUpsertWrapped(new List<SObject>{ account }, true);
     */
    public static List<AqResult> secureUpsertWrapped(List<SObject> sObjects, SObjectField field, Boolean allOrNone) {
        List<AqResult> results = new List<AqResult>();

        List<Database.UpsertResult> upsertRes = secureUpsert(sObjects, field, allOrNone);
        for (Integer i = 0; i < sObjects.size(); i++) {
            results.add(
                new AqResultBuilder()
                    .setUpsertResult(upsertRes[i], sObjects[i].getSObjectType())
                    .createAqResult()
            );
        }

        return results;
    }
    // @end-group

    // --------------------------------------------------------------------------------
    // @start-group Delete
    // --------------------------------------------------------------------------------
    
    public static List<Database.DeleteResult> insecureDelete(List<SObject> sObjects, Boolean allOrNone) {
        return Database.delete(sObjects, allOrNone, AccessLevel.SYSTEM_MODE);
    }

    public static List<Database.DeleteResult> secureDelete(SObject sObj) {
        return secureDelete(new List<SObject> {sObj}, true);
    }

    public static List<Database.DeleteResult> secureDelete(List<SObject> sObjects) {
        return secureDelete(sObjects, true);
    }

    public static List<Database.DeleteResult> secureDelete(List<SObject> sObjects, Boolean allOrNone) {
        return Database.delete(sObjects, allOrNone, AccessLevel.USER_MODE);
    }

    public static List<AqResult> secureDeleteWrapped(List<SObject> sObjects, Boolean allOrNone) {
        List<AqResult> results = new List<AqResult>();

        List<Database.DeleteResult> deleteRes = secureDelete(sObjects, allOrNone);
        for (Integer i = 0; i < sObjects.size(); i++) {
            results.add(
                new AqResultBuilder()
                    .setDeleteResult(deleteRes[i], sObjects[i].getSObjectType())
                    .createAqResult()
            );
        }

        return results;
    }
    // @end-group

    // --------------------------------------------------------------------------------
    // @start-group  Undelete
    // --------------------------------------------------------------------------------
    public static List<Database.UndeleteResult> secureUndelete(SObject sObj) {
        return secureUndelete(new List<SObject> { sObj }, true);
    }

    public static List<Database.UndeleteResult> secureUndelete(List<SObject> sObjects) {
        return secureUndelete(sObjects, true);
    }

    public static List<Database.UndeleteResult> secureUndelete(List<SObject> sObjects, Boolean allOrNone) {
        return Database.undelete(sObjects, allOrNone, AccessLevel.USER_MODE);
    }
    // @end-group
}
