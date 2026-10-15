import { hasPlanUsage, loadCredentials } from "./credentials";
import { listPlanModels } from "./planApi";

export async function planAiReady() {
  const creds = await loadCredentials();
  if (!creds || !hasPlanUsage(creds)) return false;
  try {
    await listPlanModels();
    return true;
  } catch {
    return false;
  }
}
