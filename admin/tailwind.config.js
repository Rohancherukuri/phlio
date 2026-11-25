/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "var(--bg)",
        card: "var(--card)",
        muted: "var(--muted)",
        line: "var(--line)",
        ink: "var(--ink)",
        sub: "var(--sub)",
        faint: "var(--faint)",
        brand: "var(--brand)",
        good: "var(--good)",
        bad: "var(--bad)",
      },
      fontFamily: { sans: ["Inter", "ui-sans-serif", "system-ui", "sans-serif"] },
      borderRadius: { xl: "14px", "2xl": "18px" },
    },
  },
  plugins: [],
};
