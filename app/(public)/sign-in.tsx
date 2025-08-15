import React from "react";
import { Text, TextInput, Button, View } from "react-native";

import { router } from "expo-router";

import { useSignIn } from "@/hooks/useSignIn";

export default function Page() {
  const { signInWithPassword, isLoaded } = useSignIn();

  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");

  const onSignInPress = async () => {
    if (!isLoaded) return;

    try {
      await signInWithPassword({
        email,
        password,
      });
    } catch (err) {
      console.error(JSON.stringify(err, null, 2));
    }
  };

  return (
    <View style={{ display: "flex", flex: 1 }}>
      <Text>Sign in</Text>
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
      <Button title="Continue" onPress={onSignInPress} />
      <View
        style={{
          display: "flex",
          flexDirection: "row",
          justifyContent: "center",
        }}
      >
        <Text>Don&apos;t have an account? </Text>
        <Text onPress={() => router.replace("/sign-up")}>Sign up</Text>
      </View>
    </View>
  );
}
