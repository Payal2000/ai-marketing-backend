import "dotenv/config";
import { handler } from "../functions/poller/index";

async function main() {
  const res = await handler();
  // eslint-disable-next-line no-console
  console.log(JSON.stringify(res));
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error(e);
  process.exit(1);
});

