const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const supabaseClientKey =
    supabasePublishableKey != '' ? supabasePublishableKey : supabaseAnonKey;
const authEnabled = supabaseUrl != '' && supabaseClientKey != '';
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

const appEnvironment =
    String.fromEnvironment('APP_ENV', defaultValue: 'production');
const crashlyticsEnabled =
    bool.fromEnvironment('CRASHLYTICS_ENABLED', defaultValue: true);
