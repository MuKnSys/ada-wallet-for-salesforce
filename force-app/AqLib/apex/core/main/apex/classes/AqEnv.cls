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
 * @description Returns information about current Salesforce environment and controls settings such as for debugging and logging.
 * Works in conjunction with the [Env__c](https://bitbucket.org/aquiva/aqlib/src/main/AqLib/core/main/objects/Env__c/) custom setting.
 * 
 * @group apex/core
 */
public inherited sharing class AqEnv {

    /**
     * @description Indicates with State/Country picklists are enabled in the org
     */
    public static Boolean isUsingStateCountryPicklists {
        get { return Schema.SObjectType.Account.fields.getMap().containsKey('BillingStateCode'); }
    }

    public static String namespaceOverride;
    public static String namespace {
        get {
            if (String.isNotBlank(namespaceOverride)) {
                return namespaceOverride;
            }
            if (namespace == null) {
                String envClassName = AqEnv.class.getName();
                namespace = envClassName.contains('.')
                    ? envClassName.substringBefore('.')
                    : '';
            }
            return namespace;
        }
        private set;
    }

    public static String namespacePrefix {
        get {
            if (namespacePrefix == null) {
                namespacePrefix = '';
                if (!String.isBlank(namespace)) {
                    namespacePrefix = namespace + '__';
                }
            }
            return namespacePrefix;
        }
        private set;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Date/Time override

    /**
     * @description Stores overridden DateTime value for [AqEnv.now()](#public-static-datetime-now)
     */
    public static DateTime nowOverride;
    /**
     * @description Stores overridden Date value for [AqEnv.today()](#public-static-date-today)
     */
    public static Date todayOverride;

    /**
     * @description Must be used in all apex code instead of `DateTime.now()` or `System.now()`.
     * See also [AqEnv.nowOverride](#public-nowoverride--datetime)
     * @return DateTime
     */
    public static DateTime now() {

        if (AqEnv.nowOverride != null) {
            return AqEnv.nowOverride;
        }
        //Will use today() if it's overridden
        Env__c env = Env__c.getInstance();
        if (env.nowOverride__c != null) {
            return env.nowOverride__c;
        } else if (AqEnv.TodayOverride != null) {
            return DateTime.newInstance(AqEnv.TodayOverride, DateTime.now().time());
        } else if (env.TodayOverride__c != null) {
            return DateTime.newInstance(env.TodayOverride__c, DateTime.now().time());
        }

        return DateTime.now();
    }

    /**
     * @description Must be used in all apex code instead of `Date.today()` or `System.today()`.
     * See also [AqEnv.TodayOverride](#public-todayoverride--date)
     */
    public static Date today() {

        Env__c env = Env__c.getInstance();

        //Override to now() supersedes override to today()
        if (AqEnv.nowOverride != null) {
            return AqEnv.nowOverride.date();
        } else if (env.NowOverride__c != null) {
            return env.NowOverride__c.date();
        } else if (AqEnv.TodayOverride != null) {
            return AqEnv.TodayOverride;
        } else if (env.TodayOverride__c != null) {
            return env.TodayOverride__c;
        }

        return Date.today();
    }

    public static Date todayGmt() {
        return now().dateGmt();
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //TimeZone

    @TestVisible
    private static final Integer TEST_OVERRIDE_TIME_ZONE_OFFSET_COMPANY = -4;

    /**
     * Org default isn't available programmatically
     */
    private static final String DEFAULT_TIMEZONE_SIDKEY = 'America/New_York';

    /**
     * @description No way to read this programatically
     */
    public static String defaultTimeZoneSidKey {
        get { return DEFAULT_TIMEZONE_SIDKEY; }
    }

    /**
     * @description Returns current Org time zone offset from GMT in minutes
     */
    public static Integer timeZoneOffsetCompanyInMinutes {
        get {
            if (Test.isRunningTest()) {
                return TEST_OVERRIDE_TIME_ZONE_OFFSET_COMPANY;
            }
            return getOffsetMinutes(TimeZone.getTimeZone(currentOrg.TimeZoneSidKey));
        }
    }

    /**
     * @description Returns current user time zone offset from GMT in minutes
     */
    public static Integer timeZoneOffsetUserInMinutes {
        get {
            return getOffsetMinutes(UserInfo.getTimeZone());
        }
    }

    private static Integer getOffsetMinutes(TimeZone tz) {
        Aq.requireValue('tz', tz);
        return tz.getOffset(todayGmt()) / 1000 / 60;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Debug/logging

    /**
     * @description Returns system's debug mode state. See [Env__c](https://bitbucket.org/aquiva/aqlib/src/main/AqLib/core/main/objects/Env__c/) custom setting.
     */
    public static Boolean isDebugMode {
        get { return Env__c.getInstance().DebugMode__c; }
    }

    /**
     * @description Returns the string if system is in debug mode, empty string otherwise.
     * Allows messages to be more useful in debug mode
     */
    public static String ifDebugMode(String message) {
        if (isDebugMode == true) {
            return message;
        }

        return '';
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //Sandbox

    /**
     * @description The Organization record, lazy load and only once
     */
    public static Organization currentOrg {

        get {

            if (orgRecord == null) {
                // Organization query used to request SF org configuration. CRUD/FLS enforcement omitted
                AqSoql query = new AqSoql(Organization.SObjectType)
                    .withColumns(new List<String>{
                        'Id',
                        'InstanceName',
                        'IsSandbox',
                        'DefaultLocaleSidKey',
                        'LanguageLocaleKey',
                        isUsingStateCountryPicklists ? 'CountryCode' : 'Country'
                    })
                    .withoutSecurityEnforced();
                orgRecord = (Organization) Aq.exactlyOne(
                    Organization.SObjectType,
                    (List<Organization>) Database.query(query.getQueryString())
                );
            }

            return orgRecord;

        }

    }
    private static Organization orgRecord = null;

    /**
     * @description Returns true if current org is a sandbox, false otherwise.
     */
    public static Boolean isSandbox {
        get { return currentOrg.IsSandbox; }
    }

}
