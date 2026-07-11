const CITY_SUFFIXES = ["特别行政区", "自治州", "地区", "盟", "市"];

export function normalizeCityClient(value) {
  const normalized = value.toString().trim().replace(/\s+/g, " ").toLowerCase();
  const suffix = CITY_SUFFIXES.find((candidate) =>
    normalized.endsWith(candidate)
  );
  return suffix ? normalized.slice(0, -suffix.length) : normalized;
}
