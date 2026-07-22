import type { PropsWithChildren } from "hono/jsx";
import { Grain, classes } from "@shaferllc/keel/ui";

type LayoutProps = PropsWithChildren<{
  title: string;
  description: string;
}>;

export default function Layout({ title, description, children }: LayoutProps) {
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{title}</title>
        <meta name="description" content={description} />
        <meta property="og:title" content={title} />
        <meta property="og:description" content={description} />
        <meta property="og:type" content="website" />
        <meta property="og:image" content="/screenshot.png" />
        <meta name="twitter:card" content="summary_large_image" />
        <link rel="icon" href="/icon.png" />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="" />
        <link rel="stylesheet" href="/assets/app.css" />
      </head>
      <body class={classes.body}>
        <Grain />
        {children}
      </body>
    </html>
  );
}
