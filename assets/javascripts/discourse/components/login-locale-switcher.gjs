import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

export const AVAILABLE_LOCALES = [
  { code: "zh_CN", name: "简体中文" },
  { code: "en", name: "English" },
  { code: "ja", name: "日本語" },
  { code: "de", name: "Deutsch" },
  { code: "es", name: "Español" },
  { code: "fr", name: "Français" },
  { code: "pt", name: "Português" },
  { code: "ru", name: "Русский" },
  { code: "ar", name: "العربية" },
];

export function detectCurrentLocale() {
  try {
    const params = new URLSearchParams(window.location.search);
    const paramLocale =
      params.get("tl") || params.get("lang") || params.get("locale");
    if (paramLocale) {
      const found = AVAILABLE_LOCALES.find(
        (l) =>
          l.code.toLowerCase() === paramLocale.toLowerCase() ||
          l.code.toLowerCase() === paramLocale.replace("-", "_").toLowerCase()
      );
      if (found) {
        return found.code;
      }
    }
  } catch {
    // Ignore URL parameter parsing errors in non-browser or test environments
  }

  try {
    const cookieMatch = document.cookie?.match(/(?:^|;\s*)locale=([^;]+)/);
    if (cookieMatch) {
      const cookieLocale = decodeURIComponent(cookieMatch[1]);
      const found = AVAILABLE_LOCALES.find(
        (l) =>
          l.code.toLowerCase() === cookieLocale.toLowerCase() ||
          l.code.toLowerCase() === cookieLocale.replace("-", "_").toLowerCase()
      );
      if (found) {
        return found.code;
      }
    }
  } catch {
    // Ignore cookie parsing errors
  }

  const htmlLang =
    typeof document !== "undefined" ? document.documentElement?.lang : null;
  if (htmlLang) {
    const normalized = htmlLang.replace("-", "_");
    const found = AVAILABLE_LOCALES.find(
      (l) =>
        l.code.toLowerCase() === normalized.toLowerCase() ||
        l.code.toLowerCase() === htmlLang.toLowerCase()
    );
    if (found) {
      return found.code;
    }
  }

  return "zh_CN";
}

export default class LoginLocaleSwitcher extends Component {
  get currentLocale() {
    return detectCurrentLocale();
  }

  get locales() {
    const current = this.currentLocale;
    return AVAILABLE_LOCALES.map((locale) => ({
      ...locale,
      selected: locale.code === current,
    }));
  }

  get label() {
    return i18n("where_is_my_friends.locale_switcher.label", {
      defaultValue: "Language",
    });
  }

  @action
  onLocaleChange(event) {
    const selected = event?.target?.value;
    if (!selected) {
      return;
    }

    try {
      document.cookie = `locale=${encodeURIComponent(
        selected
      )}; path=/; max-age=31536000; SameSite=Lax`;
    } catch {
      // Ignore cookie write errors
    }

    try {
      const url = new URL(window.location.href);
      url.searchParams.set("tl", selected);
      url.searchParams.set("lang", selected);
      window.location.href = url.toString();
    } catch {
      if (typeof window !== "undefined" && window.location) {
        window.location.reload();
      }
    }
  }

  <template>
    <div class="login-locale-switcher" data-test-login-locale-switcher>
      <label for="login-locale-select" class="login-locale-switcher__label">
        {{dIcon "globe"}}
        <span class="login-locale-switcher__label-text">{{this.label}}</span>
      </label>
      <select
        id="login-locale-select"
        class="login-locale-switcher__select"
        aria-label={{this.label}}
        data-test-login-locale-select
        {{on "change" this.onLocaleChange}}
      >
        {{#each this.locales as |loc|}}
          <option value={{loc.code}} selected={{loc.selected}}>
            {{loc.name}}
          </option>
        {{/each}}
      </select>
    </div>
  </template>
}
