import { useTheme, type ThemePreference } from "../theme/ThemeProvider";

const options: { id: ThemePreference; label: string }[] = [
  { id: "light", label: "Claro" },
  { id: "dark", label: "Oscuro" },
  { id: "system", label: "Sistema" },
];

export function ThemeSwitch({ className = "" }: { className?: string }) {
  const { preference, setPreference } = useTheme();
  return (
    <div className={`seg${className ? ` ${className}` : ""}`} role="group" aria-label="Tema">
      {options.map((option) => (
        <button
          key={option.id}
          type="button"
          aria-pressed={preference === option.id}
          onClick={() => setPreference(option.id)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
