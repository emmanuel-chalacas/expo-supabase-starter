import { Button, View } from "react-native";

import { useSupabase } from "@/hooks/useSupabase";

export default function Page() {
  const { signOut } = useSupabase();

  const handleSignOut = async () => {
    try {
      await signOut();
    } catch (err) {
      console.error(JSON.stringify(err, null, 2));
    }
  };

  return (
    <View
      style={{
        display: "flex",
        flex: 1,
        justifyContent: "center",
        alignItems: "center",
      }}
    >
      <Button title="Sign Out" onPress={handleSignOut} />
    </View>
  );
}
