import {
  Brand,
  Button,
  Hero,
  HeroGlow,
  HeroInner,
  Muted,
  Panel,
  Rise,
  SectionLabel,
  Shell,
} from "@shaferllc/keel/ui";

import Layout from "./layout.js";

const REPO = "https://github.com/tshafer/trim";
const RELEASES = `${REPO}/releases/latest`;

/** Feature copy lives here so the JSX below stays a layout, not a wall of text. */
const FEATURES: Array<{ title: string; body: string }> = [
  {
    title: "Any background, not just white",
    body: "Trim samples the four corners. If they agree on a color — a brand blue, a paper cream, transparent — that's the background, and everything else is your artwork.",
  },
  {
    title: "Or say what the background is",
    body: "Pick white, black, transparency only, or eyedrop a color straight off the image. One tolerance slider decides how close counts as close enough.",
  },
  {
    title: "Trim only the edges you mean",
    body: "Lock the top, right, bottom, or left and that side stays exactly where it was. Useful when only one margin is the problem.",
  },
  {
    title: "Lock the shape",
    body: "1:1, 4:3, 3:2, 16:9, or the original ratio. The crop grows around its center until it fits the shape, and never runs off the canvas.",
  },
  {
    title: "Export on your terms",
    body: "PNG, JPEG with a quality slider, or TIFF, at 25% to 200% scale. JPEG output is flattened onto white, so transparent margins never come out black.",
  },
  {
    title: "A folder at a time",
    body: "Drop a pile of images, step through them with ⌘↓, then Trim All exports every one to a folder with a -trimmed suffix.",
  },
];

const SHORTCUTS: Array<[string, string]> = [
  ["⌘O", "Open images"],
  ["⌘V", "Paste from the clipboard"],
  ["⌘P", "Eyedrop the background"],
  ["⌘S", "Save the trimmed image"],
  ["⌘C", "Copy the trimmed image"],
  ["⇧⌘S", "Trim all, to a folder"],
];

export default function Home() {
  return (
    <Layout
      title="Trim — cut the dead margin off any image"
      description="A free macOS app. Drop an image and Trim cuts the transparent, white, or solid-color margin down to the artwork. One window, one slider, live preview."
    >
      <Hero>
        <HeroGlow />
        <HeroInner class="site-column">
          <Muted class="mb-4 text-sm tracking-[0.2em] uppercase">
            <Rise step={0} as="span">
              Free · macOS 14+ · universal
            </Rise>
          </Muted>

          <Rise step={1} as="h1" class="text-[clamp(3.5rem,12vw,6.5rem)] text-ink">
            <Brand>Trim</Brand>
          </Rise>

          <Rise step={2} as="p" class="mt-5 max-w-xl text-lg leading-relaxed text-ink-soft">
            Drop an image and the dead margin disappears — the transparent border around
            an exported logo, the sea of white around a chart, the solid backdrop behind
            a product shot. One window, one slider, live preview, done.
          </Rise>

          <Rise step={3} as="div" class="mt-10 flex flex-wrap items-center gap-4">
            <Button href={RELEASES} variant="primary">
              Download for macOS
            </Button>
            <Button href={REPO} variant="ghost">
              Source on GitHub
            </Button>
          </Rise>

          <Rise step={3} as="p" class="mt-6 text-sm text-ink-soft/80">
            No network, no analytics, no permissions. It reads the files you hand it and
            writes where you tell it.
          </Rise>
        </HeroInner>
      </Hero>

      <Shell class="site-column pb-24">
        <section class="-mt-10 mb-28">
          <img
            src="/screenshot.png"
            alt="Trim showing a blue-bordered image cropped to its black artwork, with tolerance, background, edge, and aspect controls"
            width="1566"
            height="1240"
            class="w-full rounded-xl border border-line shadow-2xl"
          />
          <Muted class="mt-4 text-center text-sm">
            200 × 160 px → 140 × 140 px, with the aspect locked to 1:1 and the background
            detected automatically.
          </Muted>
        </section>

        <section class="mb-28">
          <SectionLabel as="h2">What it does</SectionLabel>
          <ul class="mt-8 grid gap-5 sm:grid-cols-2">
            {FEATURES.map((feature) => (
              <Panel as="li">
                <h3 class="font-display text-xl text-ink">{feature.title}</h3>
                <p class="mt-3 leading-relaxed text-ink-soft">{feature.body}</p>
              </Panel>
            ))}
          </ul>
        </section>

        <section class="mb-28 grid gap-10 sm:grid-cols-2">
          <div>
            <SectionLabel as="h2">Keyboard</SectionLabel>
            <dl class="mt-8 space-y-3">
              {SHORTCUTS.map(([keys, label]) => (
                <div class="flex items-baseline gap-4">
                  <dt class="w-16 shrink-0 font-mono text-sm text-ink">{keys}</dt>
                  <dd class="text-ink-soft">{label}</dd>
                </div>
              ))}
            </dl>
          </div>

          <div>
            <SectionLabel as="h2">Installing</SectionLabel>
            <p class="mt-8 leading-relaxed text-ink-soft">
              Download the disk image, open it, and drag Trim to Applications. It's
              ad-hoc signed rather than notarized, so the first launch needs a
              right-click → Open.
            </p>
            <p class="mt-4 leading-relaxed text-ink-soft">
              Or build it yourself — Swift Package Manager, no Xcode project, no
              dependencies:
            </p>
            <pre class="mt-4 overflow-x-auto rounded-lg border border-line bg-white/70 p-4 text-sm text-ink">
              <code>
                git clone {REPO}.git{"\n"}cd trim && ./make-app.sh
              </code>
            </pre>
          </div>
        </section>

        <footer class="border-t border-line pt-8">
          <p class="text-sm text-ink-soft">
            <em>Trim</em> — the set of a ship's sails; also, to cut away the excess. In
            the spirit of QuickCrop, but free.
          </p>
          <p class="mt-3 flex flex-wrap gap-5 text-sm">
            <a class="underline underline-offset-4 text-ink-soft" href={REPO}>
              GitHub
            </a>
            <a class="underline underline-offset-4 text-ink-soft" href={RELEASES}>
              Releases
            </a>
            <a class="underline underline-offset-4 text-ink-soft" href="https://keeljs.com">
              Built with Keel
            </a>
          </p>
        </footer>
      </Shell>
    </Layout>
  );
}
