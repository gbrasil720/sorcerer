import { renderToString } from "react-dom/server";
import { Landing } from "./routes/index";

/** Static HTML of the landing, injected into dist/index.html at build time. */
export const render = () => renderToString(<Landing />);
