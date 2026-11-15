# Problem Understanding — Google Maps Navigation Database

## Objective

The objective of this project is to design a PostgreSQL database for a Google Maps-like navigation platform. The database must support fast customer-facing searches, place information, live traffic updates and navigation, while also supporting analytical queries, reporting and data-quality operations.

## Business Problems (P1–P8)

| ID | Business need | Affected stakeholder/team | Workload classification |
|---|---|---|---|
| P1 | Improve the speed of near-me and open-now place searches, including searches around midnight where closing times may cross into the next day. | Travellers, Search Team | Customer-facing / Real-time |
| P2 | Improve loading time for place detail pages, including place information, opening hours and latest reviews, and the Saved tab. | Travellers, Places Team | Customer-facing / Real-time |
| P3 | Ensure live traffic conditions and road incident layers refresh at least once every minute. | Drivers, Traffic Team | Customer-facing / Real-time |
| P4 | Make typical traffic charts and road-safety reports faster to generate. | Traffic Team, Analysts | Reporting / Analytics |
| P5 | Support accurate ETAs, quick route initiation, identification of rerouting hotspots and route trend reporting. | Drivers, Routing and ETA Team | Customer-facing / Real-time and Reporting / Analytics |
| P6 | Generate a meaningful list of places that have never been used as a navigation starting point. | Data Team | Reporting / Analytics |
| P7 | Improve the speed and reliability of data-quality checks for stale ratings, closed places still used for navigation, missing opening hours and duplicate listings. | Data-quality Team, Places Team | Reporting / Analytics |
| P8 | Support faster community leaderboards, review moderation and database health reports as navigation usage grows significantly. | Local Guides, Moderation Team, Analysts | Reporting / Analytics |

## Stakeholders

- **Travellers and drivers:** Search for places, view place details, save locations and navigate.
- **Local Guides:** Contribute reviews and participate in community activities.
- **Business owners:** Maintain accurate business details and opening hours.
- **Search Team:** Maintain fast and relevant place discovery.
- **Places Team:** Manage place information, opening hours and reviews.
- **Traffic Team:** Maintain live traffic information and road incident data.
- **Routing and ETA Team:** Generate routes, calculate ETAs and monitor rerouting patterns.
- **Data-quality Team:** Identify incomplete, inconsistent and duplicate records.
- **Moderation Team:** Monitor reviews and community contributions.
- **Analytics Team:** Generate reports, leaderboards and operational insights.

## Assumptions

1. Place searches may happen at any time, including after midnight.
2. Opening hours may extend past midnight, so closing time cannot always be treated as later than opening time on the same calendar day.
3. A place may have multiple opening-hour records for different weekdays.
4. Users may save the same place in different named lists.
5. Some navigation sessions may be initiated using GPS coordinates rather than a known place listing.
6. Some navigation sessions may be anonymous, so a user reference may not always be available.
7. Live traffic readings are time-dependent and multiple readings may exist for the same road segment.
8. Incident reports may be associated with a road segment and a reporting user.
9. Not every place category necessarily has records in the supplied seed dataset.
10. Analytical workloads may scan historical records and aggregate information across multiple tables.
11. The database should preserve referential integrity while allowing legitimate optional information to remain NULL.
12. The system should support increased data volume without compromising the correctness of navigation and place information.