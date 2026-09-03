import { AddGameSection } from "../components/AddGame";
import { FileSharing } from "../components/FileSharing";
import { SdCard } from "../components/SdCard";

// SD card last: the only destructive action, kept away from the casual toggles
export function Library() {
  return (
    <>
      <AddGameSection />
      <FileSharing />
      <SdCard />
    </>
  );
}
