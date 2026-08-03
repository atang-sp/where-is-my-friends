export const HOMEPAGE_DISCOVERY_ENTRIES = Object.freeze({
  INTEREST_ONBOARDING: "interest-onboarding",
  COMMUNITY: "community",
  LOCAL: "local",
});

export function homepageDiscoveryEntry({ onboardingState, enabled }) {
  if (!enabled) {
    return HOMEPAGE_DISCOVERY_ENTRIES.LOCAL;
  }

  if (onboardingState === "pending") {
    return HOMEPAGE_DISCOVERY_ENTRIES.INTEREST_ONBOARDING;
  }

  if (onboardingState === "complete") {
    return HOMEPAGE_DISCOVERY_ENTRIES.COMMUNITY;
  }

  return HOMEPAGE_DISCOVERY_ENTRIES.LOCAL;
}
