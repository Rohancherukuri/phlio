-- Apply once to existing schemafull user tables before deploying account details.
DEFINE FIELD date_of_birth ON TABLE user TYPE option<string>;
DEFINE FIELD phone_number ON TABLE user TYPE option<string>;
DEFINE INDEX user_phone_unique ON TABLE user FIELDS phone_number UNIQUE;
