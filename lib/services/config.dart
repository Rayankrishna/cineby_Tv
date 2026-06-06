import 'package:flutter/material.dart';

// Embed providers (switched from vidlink.pro → player.videasy.net)
const String serverurl = 'https://player.videasy.net/movie/';
const String tvServerurl = 'https://player.videasy.net/tv/';

// TMDB catalog (proxied via videasy)
const String searchUrl =
    'https://db.videasy.net/3/search/multi?language=en&page=1&query=';
const String homeUrl =
    'https://db.videasy.net/3/trending/all/day?region=US&language=en';
const String topMoviesUrl =
    'https://db.videasy.net/3/discover/movie?sort_by=popularity.desc&language=en&page=1';
const String topSeriesUrl =
    'https://db.videasy.net/3/discover/tv?sort_by=popularity.desc&language=en&page=1';
const String topAnimeUrl =
    'https://db.videasy.net/3/discover/tv?with_genres=16&with_origin_country=JP|CN&sort_by=popularity.desc&language=en&page=1';

const String movieDetailUrl = 'https://db.videasy.net/3/movie';
const String movieDetailParams =
    '?append_to_response=credits,external_ids,videos&language=en';

const String tvDetailUrl = 'https://db.videasy.net/3/tv';
const String tvDetailParams =
    '?append_to_response=credits,external_ids,videos&language=en';
const String tvSeasonUrl = 'https://db.videasy.net/3/tv';
const String tvSeasonParams = '?language=en';

// Avatar picker
const String popularPeopleUrl =
    'https://db.videasy.net/3/person/popular?language=en&page=';

// Reelix backend
const String apiBaseUrl = 'https://cineby-main.vercel.app/api/v1';

// TMDB image bases
const String imgOriginal = 'https://image.tmdb.org/t/p/original';
const String imgW500 = 'https://image.tmdb.org/t/p/w500';
const String imgW300 = 'https://image.tmdb.org/t/p/w300';
const String imgW200 = 'https://image.tmdb.org/t/p/w200';
const String imgW185 = 'https://image.tmdb.org/t/p/w185';

// SharedPreferences keys
const String kPrefAccessToken = 'reelix.accessToken';
const String kPrefRefreshToken = 'reelix.refreshToken';
String kPrefAvatar(String userId) => 'reelix.avatar.$userId';

// UI palette
const Color kNetflixRed = Color(0xFFE50914);
const Color kDeepBlack = Color(0xFF0B0B10);
const Color kSurfaceGrey = Color(0xFF1A1A22);
const Color kSurfaceHi = Color(0xFF242430);
const Color kTextWhite = Colors.white;
const Color kTextGrey = Color(0xFFB3B3BB);
const Color kAccent = Color(0xFF60A5FA);
