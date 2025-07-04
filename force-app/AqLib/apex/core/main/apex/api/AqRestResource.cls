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
 * @description Base class for a REST resource.
 * @group apex/core
 */
public inherited sharing abstract class AqRestResource extends Aq.Value implements Aq.Validatable {

    ///////////////////////////////////////////////////////////////////
    // Constants

    public static final String SCOPE_TYPE_RESOURCE = 'Resource';
    public static final String SCOPE_TYPE_PROPERTY = 'Property';

    ///////////////////////////////////////////////////////////////////
    // Fields

    protected String parentName = null;
    protected List<AqResult> validationResults = null;

    ///////////////////////////////////////////////////////////////////
    //Static methods

    //Try to field corresponding field just based on name
    public static String fieldForProperty(sObjectType objectType, String propertyName) {

        sObjectField field = objectType.getDescribe().fields.getMap().get(Aq.appendPrefix(propertyName + '__c'));
        if (field == null) {
            field = objectType.getDescribe().fields.getMap().get(propertyName);
        }

        if (field != null) {
            return String.valueOf(field);
        } else {
            return null;
        }
    }

    //Maps records into resource and returns
    public static AqRestResource getResource(sObject record, System.Type resourceType) {

        Aq.requireValue('record', record);
        Aq.requireValue('resourceType', resourceType);

        //Load up resource
        AqRestResource resource = (AqRestResource) resourceType.newInstance();
        resource.get(record);

        return resource;
    }

    //Maps records into resources and returns list of resources
    public static List<AqRestResource> getResources(List<sObject> records, System.Type resourceType) {

        Aq.requireValue('records', records);
        Aq.requireValue('resourceType', resourceType);

        AqRestResource templateResource = (AqRestResource) resourceType.newInstance();

        //Load up resources
        List<AqRestResource> results = (List<AqRestResource>) templateResource.getResourceListType().newInstance();
        for (Integer i = 0; i < records.size(); i++) {
            AqRestResource resource = (AqRestResource) resourceType.newInstance();
            resource.get(records[i]);
            results.add(resource);
        }

        return results;
    }

    //Maps resources into records and upserts by Id
    public static AqResult upsertResources(List<AqRestResource> resources, Boolean allOrNothing) {

        Aq.requireNonemptyList('resources', resources);

        AqRestResource templateResource = resources[0];
        //Prepare result
        AqResult result = new AqResultBuilder().setType('UpsertResourcesResult').createAqResult();

        //Prepare to validate and insert
        List<sObject> recordsToUpsert = (List<sObject>) templateResource.getSObjectListType().newInstance();
        Map<Integer, Integer> indexMap = new Map<Integer, Integer>();
        for (Integer i = 0; i < resources.size(); i++) {

            AqRestResource resource = resources[i];

            //Add the placeholder result for this item
            AqResult resourceResult = result.addSubResult(
                new AqResultBuilder()
                    .setType('UpsertResourceResult')
                    .setLevel(AqResult.LEVEL_BUSINESS)
                    .setScopeType(SCOPE_TYPE_RESOURCE)
                    .setScope(String.valueOf(i))
                    .createAqResult()
            );

            //Validate
            resourceResult.mergeResult(resource.validate());
            if (resourceResult.hasError()) {
                continue;
            }

            sObject newObject = resource.getSObjectType().newSObject();

            try {
                resource.put(newObject);
            } catch (System.Exception e) {
                resourceResult.addSubResultAndRollup(
                    new AqResultBuilder()
                        .setException(e)
                        .setSource('resource.put()')
                        .createAqResult()
                );
                continue;
            }

            //Map from record to be inserted to original resource index
            indexMap.put(recordsToUpsert.size(), i);
            recordsToUpsert.add(newObject);
        }

        if (!recordsToUpsert.isEmpty()) {

            System.Savepoint sp = Database.setSavepoint();

            //Upsert the records
            //Never do all or nothing, allows better reporting of all results, then rollback below if failures and all-or-nothing
            List<Database.UpsertResult> upsertResults = AqDml.secureUpsert(recordsToUpsert, null, false);

            //Process the results
            Boolean hasError = false;
            for (Integer i = 0; i < upsertResults.size(); i++) {

                AqResult resourceResult = result.SubResults[indexMap.get(i)];

                if (!upsertResults[i].isSuccess()) {
                    hasError = true;
                }
                resourceResult.mergeResult(
                    new AqResultBuilder()
                        .setUpsertResult(upsertResults[i], templateResource.getSObjectType())
                        .createAqResult()
                );
                resourceResult.ReturnValue = upsertResults[i].getId();
            }

            if (allOrNothing == true && hasError == true) {
                Database.rollback(sp);
            }
        }

        result.rollupSeverity(allOrNothing, AqResult.SEVERITY_ROLLED_BACK);
        return result;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Types

    //Return its own type -- cannot do this via any kind of reflection method
    public virtual Type getResourceType() {
        return null;
    }

    //Return type of list of resource
    public virtual Type getResourceListType() {
        return null;
    }

    //Return the sObjectType associated with this resource
    public virtual sObjectType getSObjectType() {
        return null;
    }

    //Return the type of list of sObjectType
    public virtual Type getSObjectListType() {
        return null;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //sObject mapping

    //Convert the property name to corresponding sObjectField api name
    public virtual String fieldForProperty(String propertyName) {

        String result = null;
        if (this.getSObjectType() != null) {
            result = fieldForProperty(this.getSObjectType(), propertyName);
        }
        if (result == null) {
            throw new Aq.NotFoundException(AqString.format(Label.Aq_M_NoFieldEquivalent, propertyName));
        }
        return result;

    }

    //Put properties into record fields
    public virtual void put(sObject record) {}

    //Get record fields into properties
    public virtual void get(sObject record) {}

    //Return list of resources from sub-selected records
    protected List<AqRestResource> getList(sObject record, String relationshipName, Type childResourceType, Boolean required) {

        //Instantiate template resource
        AqRestResource templateChildResource = (AqRestResource)childResourceType.newInstance();
        //Get the sub-selected records
        List<sObject> childRecords = AqField.getChildRecords(
            record,
            relationshipName,
            templateChildResource.getSObjectType(),
            required
        );
        //Build the list
        return getList(childRecords, childResourceType);

    }

    //Populate a list property from list of records
    protected List<AqRestResource> getList(List<sObject> records, Type resourceType) {

        //Instantiate template resource
        AqRestResource templateResource = (AqRestResource)resourceType.newInstance();
        //Create typed result list
        List<AqRestResource> results = (List<AqRestResource>)templateResource.getResourceListType().newInstance();

        if (records != null){
            for (sObject record : records) {
                AqRestResource resource = (AqRestResource)templateResource.getResourceType().newInstance();
                resource.get(record);
                results.add(resource);
            }
        }
        return results;

    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Validation

    //Override in derived class to perform validation
    protected virtual void doValidate() {}

    //Called from a resource to cascade validation to a child resource
    protected AqResult subValidate(String parentName) {
        this.parentName = parentName + '.';
        return validate();
    }

    //Validate object and return null if all OK or a result if warnings or errors
    public AqResult validate() {

        //Prepare temporary instance result and parent name
        this.validationResults = new List<AqResult>();
        if (this.parentName == null) {
            this.parentName = '';
        }
        //Tell resource to do its validation
        this.doValidate();

        //Summarize individual results as sub-results of one parent result
        AqResult result = new AqResultBuilder()
            .setType('ValidationResult')
            .setLevel(AqResult.LEVEL_BUSINESS)
            .addSubResults(this.validationResults)
            .createAqResult();
        result.rollupSeverity();

        //Return null for success?
        if (result.Severity == AqResult.SEVERITY_SUCCESS) {
            result = null;
        }
        //Clear context
        this.validationResults = null;
        this.parentName = null;

        return result;
    }

    //Add any kind of validation error
    protected void addValidationError(String message, String scope) {
        AqResult result = new AqResultBuilder()
            .setType(Aq.ValidationException.class.getName())
            .setSeverity(AqResult.SEVERITY_ERROR)
            .setLevel(AqResult.LEVEL_BUSINESS)
            .setMessage(message)
            .setScopeType(SCOPE_TYPE_PROPERTY)
            .setScope(scope)
            .createAqResult();
        this.validationResults.add(result);
    }

    //Validate a field for requiredness.
    protected void requireProperty(String propertyName, object value) {

        if (value == null || (value instanceof String && String.isEmpty((String)value))) {
            addValidationError(
                AqString.format(Label.Aq_M_ValueRequired, this.parentName + propertyName),
                this.parentName + propertyName
            );
        }
    }

    //Validate a string value to be in specified set
    protected void requirePropertyInSet(String propertyName, String stringValue, Boolean required, Set<String> targetSet) {

        if (String.isEmpty(stringValue)) {

            if (required != true) {
                return;
            } else {
                addValidationError(AqString.format(Label.Aq_M_ValueRequired, this.parentName + propertyName), this.parentName + propertyName);
            }
        } else {

            if (!targetSet.contains(stringValue)) {
                addValidationError(
                    AqString.format(
                        Label.Aq_M_ValueMustBeInSet,
                        stringValue,
                        this.parentName + propertyName,
                        AqString.formatSet(targetSet)
                    ),
                    this.parentName + propertyName
                );
            }
        }
    }

    //Validate a string field
    protected void validateString(String propertyName, String stringValue, Boolean required, Integer maxLength) {

        AqResult result = AqTypes.validateAndConvert(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, AqTypes.DATATYPE_STRING,
            stringValue, required, maxLength
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate an integer field
    protected void validateInteger(String propertyName, Integer value, Boolean required, Integer min, Integer max) {

        if (required == true) {
            requireProperty(propertyName, value);
        }
        if (value != null) {

            if (min != null && value < min) {
                addValidationError(AqString.format(Label.Aq_M_ValueLessThanMin, value, min), this.parentName + propertyName);
            } else if (max != null && value > max) {
                addValidationError(AqString.format(Label.Aq_M_ValueGreaterThanMax, value, max), this.parentName + propertyName);
            }
        }

    }

    //Validate a Salesforce ID
    protected void validateId(String propertyName, String stringValue, Boolean required) {

        AqResult result = AqTypes.validateAndConvert(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, AqTypes.DATATYPE_ID,
            stringValue, required, null
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate a 24-hour time-only field (HH:mm)
    protected void validateTime(String propertyName, String stringValue, Boolean required) {

        AqResult result = AqTypes.validateAndConvert(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, AqTypes.DATATYPE_TIME,
            stringValue, required, null
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate an email address
    protected void validateEmail(String propertyName, String stringValue, Boolean required) {

        AqResult result = AqTypes.validateAndConvert(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, AqTypes.DATATYPE_EMAIL,
            stringValue, required, null
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate a ZIP code field
    protected void validateZipCode(String propertyName, String stringValue, Boolean required) {

        AqResult result = AqTypes.validateAndConvert(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, AqTypes.DATATYPE_ZIP,
            stringValue, required, null
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate a Social Security Number field
    protected void validateSsn(String propertyName, String stringValue, Boolean required) {

        AqResult result = AqTypes.validateAndConvert(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, AqTypes.DATATYPE_SSN, stringValue, required, null
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate string to match any Regex pattern
    protected void validatePattern(String propertyName, String value, Boolean required, String regEx, String patternLabel) {

        AqResult result = AqTypes.validatePattern(
            SCOPE_TYPE_PROPERTY, this.parentName + propertyName, value, required, regEx, patternLabel
        );
        if (result.Severity != AqResult.SEVERITY_SUCCESS) {
            this.validationResults.add(result);
        }
    }

    //Validate a sub-resource
    protected void validateResource(String propertyName, AqRestResource value, Boolean required) {

        if (required == true) {
            requireProperty(propertyName, value);
        }
        if (value == null){
            return;
        }
        AqResult result = value.subValidate(this.parentName + propertyName);
        if (result != null && result.SubResults != null) {
            this.validationResults.addAll(result.SubResults);
        }
    }

    //Validate a list for requiredness and length
    protected void validateResourceList(String propertyName, List<Object> resourceList, Boolean required, Integer minSize, Integer maxSize) {

        //Validate required
        if (required == true) {
            requireProperty(this.parentName + propertyName, resourceList);
        } else if (resourceList == null) {
            return;
        }

        //Validate for number of items
        if (minSize != null && (resourceList == null || resourceList.size() < minSize)) {
            addValidationError(
                AqString.format(Label.Aq_M_ListTooShort, this.parentName + propertyName, minSize),
                this.parentName + propertyName
            );
        } else if (maxSize != null && resourceList != null && resourceList.size() > maxSize) {
            addValidationError(
                AqString.format(Label.Aq_M_ListTooLong, this.parentName + propertyName, maxSize),
                this.parentName + propertyName
            );
        }

        if (resourceList == null) {
            return;
        }

        //Cascade validation to all items
        if (!resourceList.isEmpty() && resourceList[0] instanceof AqRestResource) {
            for (Integer i = 0; i < resourceList.size(); i++) {
                AqRestResource item = (AqRestResource)resourceList[i];
                validateResource(
                    this.parentName + propertyName + '[' + String.valueOf(i) + ']',
                    (AqRestResource)item,
                    false
                );
            }
        }

    }

}
