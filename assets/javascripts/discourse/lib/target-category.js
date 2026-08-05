export function isWhereIsMyFriendsTargetCategory(category, siteSettings) {
  const targetCategoryId = Number(
    siteSettings.where_is_my_friends_target_category_id
  );
  if (targetCategoryId > 0) {
    return Number(category?.id) === targetCategoryId;
  }

  const legacySlug =
    siteSettings.where_is_my_friends_target_category_slug?.trim();
  return Boolean(legacySlug && category?.slug === legacySlug);
}
