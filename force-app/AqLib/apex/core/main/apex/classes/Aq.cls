/**
 * Copyright (c) 2023, Aquiva Labs LLC. All rights reserved.
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
 * @description Core shared methods, classes, and interfaces.
 *
 * @group apex/core
 */

// PMD False Positive: Internal libs are ok to have many public classes and a huge class complexity.
@SuppressWarnings(
    'PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessivePublicCount, PMD.ExcessiveParameterList'
)
public inherited sharing class Aq {
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Interfaces

    /**
     * @description Implemented by anything that can be formatted to text.
     */
    public interface Formatable {
        String toString();
    }

    /**
     * @description Implemented by object that can be validated and throws exception if validation fails.
     */
    public interface Validatable {
        AqResult validate();
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Enums

    /**
     * @description Conditional operators
     */
    public enum Operator {
        EQUALS,
        NOT_EQUALS,
        GREATER_THAN,
        GREATER_THAN_OR_EQUAL,
        LESS_THAN,
        LESS_THAN_OR_EQUAL,
        IN_SET,
        IS_LIKE,
        NOT_LIKE
    }
    public static final Map<Operator, String> OPERATOR_SYMBOL_MAP = new Map<Operator, String>{
        Operator.EQUALS => '=',
        Operator.NOT_EQUALS => '<>',
        Operator.GREATER_THAN => '>',
        Operator.GREATER_THAN_OR_EQUAL => '>=',
        Operator.LESS_THAN => '<',
        Operator.LESS_THAN_OR_EQUAL => '<=',
        Operator.IN_SET => 'IN',
        Operator.IS_LIKE => 'LIKE',
        Operator.NOT_LIKE => 'NOT LIKE'
    };

    /**
     * @description Logical operators
     */
    public enum Logical {
        OP_AND,
        OP_OR,
        OP_NOT
    }
    public static final Map<Logical, String> LOGICAL_SYMBOL_MAP = new Map<Logical, String>{
        null => 'AND',
        Logical.OP_AND => 'AND',
        Logical.OP_OR => 'OR',
        Logical.OP_NOT => 'NOT'
    };

    /**
     * @description Sort directions
     */
    public enum SortDir {
        ASCEND,
        DESCEND
    }
    public static final Map<SortDir, String> SORT_DIR_SYMBOL_MAP = new Map<SortDir, String>{
        null => '',
        SortDir.ASCEND => 'ASC',
        SortDir.DESCEND => 'DESC'
    };

    public static final String NULLS_FIRST = 'NULLS FIRST';
    public static final String NULLS_LAST = 'NULLS LAST';
    /**
     * @description Null sorting
     */
    public enum NullOrder {
        NULLS_FIRST,
        NULLS_LAST
    }
    public static final Map<NullOrder, String> NULL_ORDER_SYMBOL_MAP = new Map<NullOrder, String>{
        null => '',
        NullOrder.NULLS_FIRST => NULLS_FIRST,
        NullOrder.NULLS_LAST => NULLS_LAST
    };

    private static Map<Id, RecordType> recordTypesById = null;
    private static Map<String, RecordType> recordTypesByName = null;

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Additional custom exceptions

    /**
     * @description Thrown when a business rule has been violated. In general, that means result is safe to show to the caller.
     */
    public virtual class BusinessException extends AqException {
        public BusinessException(AqResult result) {
            super(result);
        }

        public BusinessException(String message, String scopeType, String scope, String code) {
            super(code, scopeType, scope);
            this.setMessage(message);
        }

        public BusinessException(String message, String scopeType, String scope) {
            this(message, scopeType, scope, null);
        }
    }

    /**
     * @description Thrown when general validation fails.
     */
    public virtual class ValidationException extends BusinessException {
        public ValidationException(AqResult result) {
            super(result);
        }

        public ValidationException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public ValidationException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }
    }

    /**
     * @description Thrown specifically in UI environment, intended to be show to a user.
     */
    public virtual class UserException extends BusinessException {
        public UserException(AqResult result) {
            super(result);
        }

        public UserException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public UserException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }
    }

    /**
     * @description Thrown when record is not found.
     */
    public virtual class NotFoundException extends BusinessException {
        public NotFoundException(AqResult result) {
            super(result);
        }

        public NotFoundException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public NotFoundException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }
    }

    /**
     * @description Thrown when wrong number of records found.
     */
    public virtual class RecordCountException extends BusinessException {
        public RecordCountException(AqResult result) {
            super(result);
        }

        public RecordCountException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public RecordCountException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }
    }

    /**
     * @description Thrown on CRUD/FLS or other permission rule violated
     */
    public virtual class PermissionException extends BusinessException {
        public PermissionException(AqResult result) {
            super(result);
        }

        public PermissionException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public PermissionException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }
    }
    /**
     * @description Thrown on CRUD/FLS permission rule violated on SOQL query
     */
    public virtual class QueryPermissionException extends PermissionException {
        public QueryPermissionException(AqResult result) {
            super(result);
        }

        public QueryPermissionException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public QueryPermissionException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }

        public QueryPermissionException(QueryException originException) {
            Map<String, Set<String>> removedFields = originException.getInaccessibleFields();
            if (!removedFields.isEmpty()) {
                String exceptionMessage = buildMessage(removedFields);
                this.setMessage(exceptionMessage);
            }
        }

        private String buildMessage(Map<String, Set<String>> removedFields) {
            String exceptionMessage = Label.Aq_M_InsufficientPrivilege;

            if (AqEnv.isDebugMode) {
                List<String> objectMessages = new List<String>();
                for (String objKey : removedFields.keySet()) {
                    List<String> fields = new List<String>(removedFields.get(objKey));
                    objectMessages.add(objKey + ' (' + String.join(fields, ', ') + ')');
                }
                exceptionMessage +=
                    '\nRequired permission: ' +
                    AccessType.READABLE +
                    '.\n' +
                    String.join(objectMessages, '\n');
            }
            return exceptionMessage;
        }
    }

    /**
     * @description Thrown on any duplicate record exception
     */
    public virtual class DuplicateException extends BusinessException {
        public DuplicateException(AqResult result) {
            super(result);
        }

        public DuplicateException(String message, String scopeType, String scope, String code) {
            super(message, scopeType, scope, code);
        }

        public DuplicateException(String message, String scopeType, String scope) {
            super(message, scopeType, scope);
        }
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Validation

    /**
     * @description Throw a validation exception if result has an error.
     */
    public static void validate(Validatable objectToValidate) {
        validate(objectToValidate, null);
    }

    /**
     * @description Throw a validation exception if result has an error.
     */
    public static void validate(Validatable objectToValidate, String resultType) {
        AqResult result = objectToValidate.validate();
        if (result != null && result.hasError()) {
            if (!String.isEmpty(resultType)) {
                result.Type = resultType;
            }
            throw new ValidationException(result);
        }
    }

    /**
     * @description Require a value.
     */
    public static void requireValue(String valueName, Object value) {
        if (value == null || value == '') {
            throw new ValidationException(AqString.format(Label.Aq_M_ValueRequired, valueName));
        }
    }

    /**
     * @description Require value to be in specified set of values.
     */
    public static void requireValueInSet(String valueName, String value, Set<String> validValues, Boolean required) {
        if (required == true && String.isEmpty(value)) {
            throw new ValidationException(AqString.format(Label.Aq_M_ValueRequired, valueName));
        }
        if (!validValues.contains(value)) {
            throw new ValidationException(
                AqString.format(Label.Aq_M_ValueMustBeInSet, value, valueName, AqString.formatSet(validValues))
            );
        }
    }

    /**
     * @description Require value to be in specified set of values.
     */
    public static void requireValueInSet(String valueName, String value, Set<String> validValues) {
        requireValueInSet(valueName, value, validValues, true);
    }

    /**
     * @description Require list to be present and not empty
     */
    public static void requireNonemptyList(String valueName, List<Object> value) {
        requireValue(valueName, value);
        if (value.isEmpty()) {
            throw new ValidationException(AqString.format(Label.Aq_M_ValueListEmpty, valueName));
        }
    }

    public static Boolean isEmptyList(List<Object> val) {
        return val == null || val.isEmpty();
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group SObject methods

    /**
     * @description Convenience function for easier reading when evaluating result of SOQL
     */
    public static Boolean exists(List<SObject> sObjectList) {
        return !sObjectList.isEmpty();
    }

    /**
     * @description Throws if there's not at least one record in result set.
     */
    public static List<SObject> atLeastOne(SObjectType objectType, List<SObject> sObjectList) {
        if (sObjectList.isEmpty()) {
            throw new NotFoundException(AqString.format(Label.Aq_M_RecordNotFound, String.valueOf(objectType)));
        }

        return sObjectList;
    }

    /**
     * @description Throws if there's not exactly one record in result set.
     */
    public static SObject exactlyOne(SObjectType objectType, List<SObject> sObjectList) {
        if (sObjectList.isEmpty()) {
            throw new NotFoundException(AqString.format(Label.Aq_M_RecordNotFound, String.valueOf(objectType)));
        } else if (sObjectList.size() > 1) {
            throw new RecordCountException(AqString.format(Label.Aq_M_TooManyRecords, String.valueOf(objectType)));
        }

        return sObjectList[0];
    }

    /**
     * @description Throws if there are more than one record in result set.
     */
    public static SObject atMostOne(SObjectType objectType, List<SObject> sObjectList) {
        if (sObjectList.isEmpty()) {
            return null;
        } else if (sObjectList.size() > 1) {
            throw new RecordCountException(AqString.format(Label.Aq_M_TooManyRecords, String.valueOf(objectType)));
        }

        return sObjectList[0];
    }

    /**
     * @description Filters list of SObjects with the given recordTypeId
     */
    public static List<SObject> filterByRecordType(List<SObject> records, Id recordTypeId) {
        Aq.requireValue('records', records);
        Aq.requireValue('RecordTypeId', recordTypeId);

        List<SObject> filteredRecords = new List<SObject>();
        for (SObject record : records) {
            if (((Id) record.get(AqField.RECORD_TYPE_ID)) == recordTypeId) {
                filteredRecords.add(record);
            }
        }
        return filteredRecords;
    }

    /**
     * @description Returns set of Ids by scanning all records in list for specified Id field.
     */
    public static Set<Id> getIdSet(List<SObject> records, SObjectField idField) {
        if (records == null) {
            return new Set<Id>();
        }

        Set<Id> idSet = new Set<Id>();
        for (SObject record : records) {
            if (record.get(idField) != null) {
                idSet.add((Id) record.get(idField));
            }
        }

        return idSet;
    }

    /**
     * @description Returns set of Strings by scanning all records in list for specified fieldName.
     */
    public static Set<String> getFieldValuesFromRecords(List<SObject> records, SObjectField fieldName) {
        if (records == null) {
            return new Set<String>();
        }
        Set<String> valSet = new Set<String>();
        for (SObject record : records) {
            Object val = record.get(fieldName);
            if (val != null) {
                valSet.add(String.valueOf(val));
            }
        }
        return valSet;
    }

    // PMD False positive: That query retrieve a static resource body by resource name and should be done in a system context.
    // This method is supposed to retrieve static resources with application configuration or for test data creation.
    @SuppressWarnings('PMD.AvoidDirectSoqlsOutsideOfTests')
    /**
     * @description Grab the string body from a static resource
     */
    public static String getStringFromResource(String resourceName) {
        StaticResource resource = (StaticResource) Aq.exactlyOne(
            StaticResource.SObjectType,
            [SELECT Id, Body FROM StaticResource WHERE Name = :resourceName]
        );
        return resource.Body.toString();
    }

    /**
     * @description Grab a serialized object from a static resource
     */
    public static Object getObjectFromResource(String resourceName, Type resourceType) {
        return JSON.deserialize(getStringFromResource(resourceName), resourceType);
    }

    /**
     * @description Convert set of object to list of object
     */
    public static List<Object> getObjectList(Set<SObjectField> objectSet) {
        List<Object> result = new List<Object>();
        for (SObjectField item : objectSet) {
            result.add(item);
        }

        return result;
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Record Type methods

    // PMD False positive: This SOQL is specific and won't be re-used, hence it's fine to create it specifically for this method.
    @SuppressWarnings('PMD.AvoidDirectSoqlsOutsideOfTests')
    private static void loadRecordTypeMaps() {
        if (recordTypesById == null) {
            List<RecordType> recordTypes = [
                SELECT Id, SobjectType, Name, DeveloperName
                FROM RecordType
                WITH SECURITY_ENFORCED
                LIMIT 10000
            ];
            recordTypesById = new Map<Id, RecordType>(recordTypes);
            recordTypesByName = new Map<String, RecordType>();
            for (RecordType rt : recordTypes) {
                recordTypesByName.put(rt.SobjectType + '|' + rt.DeveloperName, rt);
            }
        }
    }

    /**
     * @description Get all record types map with its object and developer name as the key
     */
    public static Map<String, RecordType> getAllRecordTypes() {
        loadRecordTypeMaps();
        return recordTypesByName;
    }

    /**
     * @description Get a record type by its object and developer name
     */
    public static RecordType getRecordTypeByName(SObjectType objectType, String developerName) {
        loadRecordTypeMaps();
        return recordTypesByName.get(objectType + '|' + developerName);
    }

    /**
     * @description Returns Id for record type name
     */
    public static Id getRecordTypeId(SObjectType objectType, String developerName) {
        RecordType rt = getRecordTypeByName(objectType, developerName);
        if (rt == null) {
            return null;
        }

        return rt.Id;
    }

    /**
     * @description Get the display label for record type.
     */
    public static String getRecordTypeLabel(SObjectType objectType, String developerName) {
        RecordType rt = getRecordTypeByName(objectType, developerName);
        if (rt == null) {
            return null;
        }

        return rt.Name;
    }

    /**
     * @description Get the `Schema.RecordTypeInfo` for record type.
     */
    public static RecordTypeInfo getRecordTypeInfoByName(String objectTypeName, String developerName) {
        return AqSObject.getObjectDescribe(objectTypeName).getRecordTypeInfosByDeveloperName().get(developerName);
    }

    /**
     * @description Returns true if the record has one of the specific record type names
     */
    public static Boolean hasRecordType(SObject record, Set<String> developerNames) {
        if (record == null || record.get('RecordTypeId') == null) {
            return false;
        }

        loadRecordTypeMaps();

        RecordType rt = recordTypesById.get((Id) record.get('RecordTypeId'));

        return developerNames.contains(rt.DeveloperName);
    }

    /**
     * @description Returns true if the record has the specific record type name
     */
    public static Boolean isRecordType(SObject record, String developerName) {
        loadRecordTypeMaps();

        RecordType rt = recordTypesById.get((Id) record.get('RecordTypeId'));

        return rt.DeveloperName == developerName;
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Namespace prefix handling

    public static String appendPrefix(String valueToPrefix) {
        if (
            String.isNotBlank(valueToPrefix) &&
            String.isNotBlank(AqEnv.namespacePrefix) &&
            valueToPrefix.countMatches('__') == 1
        ) {
            return AqEnv.namespacePrefix + valueToPrefix;
        }
        return valueToPrefix;
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Null-safe operations

    /**
     * @description Returns empty String in Null case.
     */
    public static String ifNull(Object value) {
        return ifNull(value, AqString.EMPTY);
    }

    public static String ifNull(String value, String defaultValue) {
        if (String.isEmpty(value)) {
            return defaultValue;
        }

        return value;
    }

    public static String ifNull(Object value, String defaultValue) {
        if (value == null) {
            return defaultValue;
        }

        return String.valueOf(value);
    }

    public static Integer ifNull(Integer value, Integer defaultValue) {
        if (value == null) {
            return defaultValue;
        }

        return value;
    }

    public static Integer ifNull(Decimal value, Integer defaultValue) {
        if (value == null) {
            return defaultValue;
        }

        return Integer.valueOf(value);
    }

    public static Decimal ifNull(Decimal value, Decimal defaultValue) {
        if (value == null) {
            return defaultValue;
        }

        return value;
    }

    public static Date ifNull(Date value, Date defaultValue) {
        if (value == null) {
            return defaultValue;
        }

        return value;
    }
    // @end-group

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // @start-group Misc

    /**
     * @description Returns all SObject fields maped by SObject name
     */
    public static Map<String, Set<String>> getSObjectFieldNames(List<SObject> records) {
        Map<String, Set<String>> objectFields = new Map<String, Set<String>>();
        for (SObject sobj : records) {
            if (sobj == null) {
                continue;
            }
            String sObjTypeName = String.valueOf(sobj.getSObjectType());
            Set<String> fields = objectFields.containsKey(sObjTypeName)
                ? objectFields.get(sObjTypeName)
                : new Set<String>();
            fields.addAll(sobj.getPopulatedFieldsAsMap().keySet());
            objectFields.put(sObjTypeName, fields);
        }

        return objectFields;
    }

    // PMD False Positive: It's describing a field, not an object.
    @SuppressWarnings('PMD.EagerlyLoadedDescribeSObjectResult')
    /**
     * @description Method used to split String between fields based on each field length if value is blank, all fields will be cleared.
     */
    public static void splitStringIntoSObjectFields(SObject sobj, List<Schema.SObjectField> fields, String value) {
        if (fields == null || fields.isEmpty() || sobj == null) {
            return;
        }

        String valueLocal = value != null ? value : '';

        for (Schema.SObjectField field : fields) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            Schema.DisplayType fType = fieldDescribe.getType();
            Boolean isStringField =
                fType == Schema.DisplayType.STRING ||
                fType == Schema.DisplayType.ENCRYPTEDSTRING ||
                fType == Schema.DisplayType.TEXTAREA;
            if (!isStringField) {
                throw new ValidationException(Label.Aq_Unsupported_Field_Type);
            }
            Integer fieldLength = fieldDescribe.getLength();

            String fValue = valueLocal.left(fieldLength);
            valueLocal = valueLocal.substringAfter(fValue);
            sobj.put(field, fValue);
        }

        if (!String.isBlank(valueLocal)) {
            throw new ValidationException(Label.Aq_Value_Wont_FitInFields);
        }
    }

    /**
     * @description Method used to abbreviate text and textarea SObject fields according to the defined field length.
     * Use this method before DML operations to avoid exceptions in case of either field constraints or field value source is out of your control.
     */
    public static void abbreviateExcessiveTextFields(SObject entity) {

        Set<DisplayType> textDisplayTypes = new Set<DisplayType>{
            DisplayType.TEXTAREA, DisplayType.STRING
        };

        Map<String, Object> fieldNameToValueMap = entity.getPopulatedFieldsAsMap();

        for (String fieldName : fieldNameToValueMap.keySet()) {

            DescribeFieldResult fieldDescribe = AqField.getToken(entity.getSObjectType(), fieldName).getDescribe();
            if (textDisplayTypes.contains(fieldDescribe.getType())) {

                String fieldValue = (String) fieldNameToValueMap.get(fieldName);

                entity.put(
                    fieldName,
                    fieldDescribe.getLength() > 4 // Minimum abbreviation width is 4
                        ? fieldValue.abbreviate(fieldDescribe.getLength())
                        : fieldValue.left(fieldDescribe.getLength())
                );
            }
        }
    }

    /**
     * @description Returns SObjects mapped by value of `parentField`
     */
    public static Map<Id, List<SObject>> toMapByParentId(List<SObject> records, SObjectField parentField) {
        return toMapByParentId(records, parentField, new Set<Id>());
    }

    public static Map<Id, List<SObject>> toMapByParentId(
        List<SObject> records,
        SObjectField parentField,
        Set<Id> parentKeys
    ) {
        Aq.requireValue('records', records);
        Aq.requireValue('parentField', parentField);
        Aq.requireValue('parentKeys', parentKeys);
        Set<Id> parentKeysCopy = new Set<Id>(parentKeys);

        Map<Id, List<SObject>> mapByParentId = new Map<Id, List<SObject>>();
        if (records.isEmpty()) {
            return mapByParentId;
        }

        for (SObject record : records) {
            Id parentId = (Id) record.get(parentField);
            if (parentId == null) {
                continue;
            }
            List<SObject> values = mapByParentId.containsKey(parentId)
                ? mapByParentId.get(parentId)
                : new List<SObject>();
            values.add(record);
            mapByParentId.put(parentId, values);
            parentKeysCopy.remove(parentId);
        }
        for (Id parentKey : parentKeysCopy) {
            if (!mapByParentId.containsKey(parentKey)) {
                mapByParentId.put(parentKey, new List<SObject>());
            }
        }
        return mapByParentId;
    }

    /**
     * @description Returns SObjects mapped by compound value of `parentFields`,
     * see [toMapByParentId()](#public-static-mapidlistsobject-tomapbyparentidlistsobject-records-sobjectfield-parentfield)
     * and [getConcatenatedValue()](#public-static-string-getconcatenatedvaluesobject-record-listsobjectfield-fields)
     */
    public static Map<String, List<SObject>> toMapByCompoundId(List<SObject> records, List<SObjectField> parentFields) {
        Aq.requireValue('records', records);
        Aq.requireNonemptyList('parentFields', parentFields);

        Map<String, List<SObject>> mapByParentId = new Map<String, List<SObject>>();
        if (records.isEmpty()) {
            return mapByParentId;
        }

        for (SObject record : records) {
            String keyCompound = getConcatenatedValue(record, parentFields);
            List<SObject> values = mapByParentId.containsKey(keyCompound)
                ? mapByParentId.get(keyCompound)
                : new List<SObject>();
            values.add(record);
            mapByParentId.put(keyCompound, values);
        }
        return mapByParentId;
    }

    /**
     * @description Returns SObjects mapped by value of `innerParentId` and then by `outerParentId`.
     * See [toMapByParentId()](#public-static-mapidlistsobject-tomapbyparentidlistsobject-records-sobjectfield-parentfield)
     */
    public static Map<Id, Map<Id, List<SObject>>> toMapByParentIdByParentId(
        List<SObject> records,
        SObjectField outerParentId,
        SObjectField innerParentId
    ) {
        Aq.requireValue('records', records);
        Aq.requireValue('outerParentId', outerParentId);
        Aq.requireValue('innerParentId', innerParentId);

        Map<Id, Map<Id, List<SObject>>> result = new Map<Id, Map<Id, List<SObject>>>();
        if (records.isEmpty()) {
            return result;
        }

        for (SObject record : records) {
            Id outerKey = (Id) record.get(outerParentId);
            if (!result.containsKey(outerKey)) {
                result.put(outerKey, new Map<Id, List<SObject>>());
            }
            Map<Id, List<SObject>> innerMap = result.get(outerKey);
            Id innerKey = (Id) record.get(innerParentId);
            if (!innerMap.containsKey(innerKey)) {
                innerMap.put(innerKey, new List<SObject>());
            }
            innerMap.get(innerKey).add(record);
        }
        return result;
    }

    /**
     * @description An utility to assemble compound string value for a given SObject and given fields separated by ':'
     * (e.g. 'Foo:Bar:777').
     */
    public static String getConcatenatedValue(SObject record, List<SObjectField> fields) {
        List<String> values = new List<String>();
        for (SObjectField fieldInfo : fields) {
            String value = Aq.ifNull(record.get(fieldInfo));
            if (String.isNotBlank(value)) {
                values.add(value);
            }
        }
        return String.join(values, AqString.KEY_SEPARATOR);
    }

    /**
     * @description Method used to concatenate values of related fields into single string
     * (ex: Access Token stored in 5 different fields because of it`s length)
     */
    public static String concatObjectStringFields(SObject sobj, List<Schema.SObjectField> fields) {
        String res = '';
        if (fields == null || fields.isEmpty() || sobj == null) {
            return res;
        }

        for (Schema.SObjectField field : fields) {
            String fieldVal = (String) sobj.get(field);
            if (!String.isBlank(fieldVal)) {
                res += fieldVal;
            }
        }

        return res;
    }

    // @end-group

    /**
     * @description Can be extended by a class that should be able to be compared for equality.
     */
    public abstract class Value {
        public Boolean equals(Object obj) {
            if (obj == null) {
                return false;
            }

            return JSON.serialize(this) == JSON.serialize(obj);
        }

        public Integer hashCode() {
            return JSON.serialize(this).hashCode();
        }
    }
}
