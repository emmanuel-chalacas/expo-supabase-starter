# 💻 Application Overview

The application is pretty simple. Users can sign up, sign in, and sign out.

## Get Started

1. Configure Supabase:

- If you haven't already, create an new account on [Supabase](https://supabase.com/).
- Create a new project and obtain your Supabase Project URL and API key.
- Rename `.env.example` to `.env`
- Update the `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_KEY` variables in the `.env` file with your Supabase URL and API key respectively.

Note: By default Supabase Auth requires email verification before a session is created for the users. To support email verification you need to go to the [Email Templates](https://supabase.com/dashboard/project/_/auth/templates) page. Select the project that you just created and replace the Message Body with the following:\_

```html
<h2>Confirm your signup</h2>

<p>{{ .Token }}</p>
```

2. Clone the repository to your local machine:

```bash
git clone https://github.com/FlemingVincent/expo-supabase-starter.git
```

3. Navigate to the project directory:

```bash
cd expo-supabase-starter
```

4. Replace environment variables:

- Rename `.env.example` to `.env`
- Update the `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_KEY` variables in the `.env` file with your Supabase URL and API key respectively.

5. Install the required dependencies:

```bash
bun install
```

6. Start the Expo development server:

```bash
npx expo start --clear --reset-cache
```
