import { Stack } from "expo-router";

export default function PublicLayout() {
  return (
    <Stack initialRouteName="welcome">
      <Stack.Screen
        name="welcome"
        options={{
          title: "Welcome",
        }}
      />
      <Stack.Screen
        name="sign-up"
        options={{
          title: "Sign Up",
        }}
      />
      <Stack.Screen
        name="sign-in"
        options={{
          title: "Sign In",
        }}
      />
    </Stack>
  );
}
