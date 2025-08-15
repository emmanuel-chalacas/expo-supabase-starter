import * as React from "react";
import { Text, TextInput, Button, View } from "react-native";

import { router } from "expo-router";

import { useSignUp } from "@/hooks/useSignUp";

export default function Page() {
  const { isLoaded, signUp, verifyOtp } = useSignUp();

  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [pendingVerification, setPendingVerification] = React.useState(false);
  const [token, setToken] = React.useState("");

  const onSignUpPress = async () => {
    if (!isLoaded) return;

    try {
      await signUp({
        email,
        password,
      });
      setPendingVerification(true);
    } catch (err) {
      console.error(JSON.stringify(err, null, 2));
    }
  };

  const onVerifyPress = async () => {
    if (!isLoaded) return;

    try {
      await verifyOtp({
        email,
        token,
      });
    } catch (err) {
      console.error(JSON.stringify(err, null, 2));
    }
  };

  if (pendingVerification) {
    return (
      <>
        <Text>Verify your email</Text>
        <TextInput
          value={token}
          placeholder="Enter your verification code"
          onChangeText={(token) => setToken(token)}
        />
        <Button title="Verify" onPress={onVerifyPress} />
      </>
    );
  }

  return (
    <View
      style={{
        display: "flex",
        flex: 1,
      }}
    >
      <>
        <Text>Sign up</Text>
        <TextInput
          autoCapitalize="none"
          value={email}
          placeholder="Enter email"
          onChangeText={(email) => setEmail(email)}
        />
        <TextInput
          value={password}
          placeholder="Enter password"
          secureTextEntry={true}
          onChangeText={(password) => setPassword(password)}
        />
        <Button title="Continue" onPress={onSignUpPress} />
        <View
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "center",
          }}
        >
          <Text>Already have an account? </Text>
          <Text onPress={() => router.replace("/sign-in")}>Sign in</Text>
        </View>
      </>
    </View>
  );
}
