// OAuth client ids for Sign in with Google / Apple.
//
// These are public identifiers (they ship inside every app build), not
// secrets. They are used when the app is run without
// `--dart-define-from-file=dart_defines.json` (e.g. from the IDE's Run
// button); a --dart-define of the same name still wins.

const kGoogleServerClientId = "597129978468-6f9f271e4s5tue0ue8hd3fih63kdglu8.apps.googleusercontent.com";
const kGoogleIosClientId = "597129978468-mt2d7kgh8ucujl758fq35rn2kh5m71j3.apps.googleusercontent.com";
const kAppleServiceId = "com.rohan.phlio.signin";
