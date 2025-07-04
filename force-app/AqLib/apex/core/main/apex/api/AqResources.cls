/*
 * Copyright (c) 2020, Aquiva Labs LLC. All rights reserved.
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
 * @description Generic REST resources for standard objects
 * @group apex/core
 */
public inherited sharing class AqResources {

    //Any address
    public virtual class Address extends AqRestResource {

        public String Type {get;set;}
        public String Street {get;set;}
        public String City {get;set;}
        public String State {get;set;}
        public String PostalCode {get;set;}
        public String Country {get;set;}

        //Empty constructor
        public Address() {}

        //Full constructor
        public Address(String type, String street, String city, String state, String postalCode, String country) {
            this.Type = type;
            this.Street = street;
            this.City = city;
            this.State = state;
            this.PostalCode = postalCode;
            this.Country = country;
        }

        //Construct from Salesforce address
        public Address(sObject record, String type, String addressNamePrefix, Boolean isCustom) {

            String suffix = isCustom == true ? '__c' : '';

            this.Type = type;
            this.Street = AqField.getString(record, AqField.getToken(record, addressNamePrefix + 'Street' + suffix));
            this.City = AqField.getString(record, AqField.getToken(record,addressNamePrefix + 'City' + suffix));
            this.State = AqField.getString(record, AqField.getToken(record,addressNamePrefix + 'State' + (AqEnv.IsUsingStateCountryPicklists == true ? 'Code' : '') + suffix));
            this.PostalCode = AqField.getString(record, AqField.getToken(record,addressNamePrefix + 'PostalCode' + suffix));
            this.Country = AqField.getString(record, AqField.getToken(record,addressNamePrefix + 'Country' + (AqEnv.IsUsingStateCountryPicklists == true ? 'Code' : '') + suffix));

        }

        //Save into record
        public void put(sObject record, String addressNamePrefix, Boolean isCustom) {

            String suffix = isCustom == true ? '__c' : '';

            AqField.put(record, AqField.getToken(record, addressNamePrefix + 'Street' + suffix), this.Street);
            AqField.put(record, AqField.getToken(record, addressNamePrefix + 'City' + suffix), this.City);
            AqField.put(record, AqField.getToken(record,addressNamePrefix + 'State' + (AqEnv.IsUsingStateCountryPicklists == true ? 'Code' : '') + suffix), this.State);
            AqField.put(record, AqField.getToken(record, addressNamePrefix + 'PostalCode' + suffix), this.PostalCode);
            String country = String.isEmpty(this.Country) ? (String)AqEnv.CurrentOrg.get('CountryCode') : this.Country;
            AqField.put(record, AqField.getToken(record,addressNamePrefix + 'Country' + (AqEnv.IsUsingStateCountryPicklists == true ? 'Code' : '') + suffix), country);

        }

        //Validate all values
        protected virtual override void doValidate() {

            validateString('Street', this.Street, true, 255);
            validateString('City', this.City, true, 40);
            validateString('State', this.State, true, 2);
            validateString('PostalCode', this.PostalCode, true, 20);

        }

    }

    //Any phone number
    public virtual class Phone extends AqRestResource {

        public String Type {get;set;}
        public String PhoneNumber {get;set;}

        //Empty constructor
        public Phone() {}

        //Full constructor
        public Phone(String type, String phoneNumber) {
            this.Type = type;
            this.PhoneNumber = phoneNumber;
        }

    }

    //Any email address
    public virtual class Email extends AqRestResource {

        public String Type {get;set;}
        public String EmailAddress {get;set;}

        //Empty constructor
        public Email() {}

        //Full constructor
        public Email(String type, String emailAddress) {
            this.Type = type;
            this.EmailAddress = emailAddress;
        }

        //Validate all values
        protected virtual override void doValidate() {
            validateEmail('EmailAddress', this.EmailAddress, true);
        }

    }

    //Any contact
    public virtual class AqContact extends AqRestResource {

        public String Id {get;set;}
        public String AccountId {get;set;}
        public String FirstName {get;set;}
        public String LastName {get;set;}
        public Date Birthdate {get;set;}
        public List<Address> Addresses {get;set;}
        public List<Phone> Phones {get;set;}
        public List<Email> Emails {get;set;}

        //Empty constructor
        public AqContact() {}

        //Name constructor
        public AqContact(String firstName, String lastName) {
            this.FirstName = firstName;
            this.LastName = lastName;
        }

        //Validate all values
        protected virtual override void doValidate() {

            validateId('AccountId', this.AccountId, false);
            validateString('FirstName', this.FirstName, true, 40);
            validateString('LastName', this.LastName, true, 80);
            validateResourceList('Addresses', this.Phones, false, 0, 2);
            validateResourceList('Phones', this.Phones, false, 0, 4);
            validateResourceList('Emails', this.Emails, false, 0, 4);

        }

         //For testing -- remove Salesforce IDs and anything else that's nondeterministic
        public void stripUniqueData() {
            this.Id = null;
            this.AccountId = null;
        }

        //Quick add for address
        public void addAddress(Address address) {

            if (this.Addresses == null)
                this.Addresses = new List<Address>();
            this.Addresses.add(address);

        }

        //Get an address by its type
        public Address getAddress(String type) {

              if (this.Addresses == null)
                  return null;
              else
                  for (Address address : this.Addresses)
                      if (address.Type == type)
                          return address;

              return null;

        }

        //Quick add for phone
        public void addPhone(String type, String phoneNumber) {

            if (String.isEmpty(phoneNumber))
                return;

            if (this.Phones == null)
                this.Phones = new List<Phone>();

            this.Phones.add(new Phone(type, phoneNumber));

        }

        //Get a phone number by its type
        public String getPhone(String type) {

              if (this.Phones == null)
                  return null;
              else
                  for (Phone phone : this.Phones)
                      if (phone.Type == type)
                          return phone.PhoneNumber;

              return null;

        }

        //Quick add for email address
        public void addEmail(String type, String emailAddress) {

            if (String.isEmpty(emailAddress))
                return;

            if (this.Emails == null)
                this.Emails = new List<Email>();
            this.Emails.add(new Email(type, emailAddress));

        }

        //Get an email address by its type
        public String getEmail(String type) {

              if (this.Emails == null)
                  return null;
              else
                  for (Email email : this.Emails)
                      if (email.Type == type)
                          return email.EmailAddress;

              return null;

        }

    }

}
