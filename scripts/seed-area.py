#!/usr/bin/env python3
"""Club cricket around Hemel Hempstead, Watford, Harrow and North London.

Fills a local stack with 36 clubs in two Saturday leagues: a squad each with
profiles filled in, three rounds of league cricket already played ball by ball,
this Saturday's round with availability marked, nets, an end-of-season dinner
with tickets sold, club chats, club shops, a T20 in progress right now, and a
5-over game this evening that nobody has started scoring yet.

Everything goes through the API the apps use, so every account can sign in and
every scorecard, season figure and league result is the engine's own. The one
shortcut is marking the email addresses confirmed in Postgres: a code per
player through Mailpit is the slow part and proves nothing new.

Club names follow the clubs that actually play in these areas, so the fixture
list reads like the area. Grounds are named where they are well known and
otherwise given as the locality, and coordinates are approximate. Every
person is invented, and names that belong to well-known cricketers and public
figures are refused by the generator.

    ./scripts/seed-area.py                          # API_BASE, or 127.0.0.1:$API_PORT
    API_BASE=http://127.0.0.1:8080 ./scripts/seed-area.py

Re-runnable: accounts sign back in, clubs, fixtures and threads that already
exist are reused, and a match that has been played is not played again.
Everyone's password is password123; the accounts worth knowing are printed at
the end.

On a shared server
------------------
Use --invented, and --note to say on every club that the data is a demo:

    API_BASE=https://int.fishers.cloud ./scripts/seed-area.py \
      --invented --clubs 8 --rounds 2 --manifest .dev/seed-int.json

Hashing a password is deliberately memory-hungry, so the default there is 3
requests at a time: sixteen at once took an API with a 512Mi limit over it and
Kubernetes killed the pod mid-run.

Nothing here can be undone through the API — there is no delete-club endpoint
— so removing it again means the database. Everyone this script makes has an
address at @fishers.test, which is the handle to pull:

    kubectl exec -n fishers-<ring> fishers-db-0 -- psql -U postgres -d fishers -c "
      DELETE FROM clubs WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@fishers.test');
      DELETE FROM users WHERE email LIKE '%@fishers.test';"

Check what that would take first — a real account of yours at that domain
would go with it:

    SELECT email FROM users WHERE email LIKE '%@fishers.test';
"""
from __future__ import annotations

import concurrent.futures as cf
import datetime as dt
import json
import os
import random
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from zoneinfo import ZoneInfo

import argparse

API = os.environ.get("API_BASE") or f"http://127.0.0.1:{os.environ.get('API_PORT', '7312')}"
V1 = API.rstrip("/") + "/api/v1"
PASSWORD = "password123"
PG_CONTAINER = os.environ.get("PG_CONTAINER", "fishers-postgres")
LONDON = ZoneInfo("Europe/London")
# The same world on every run: same people, same clubs, same scorecards.
rng = random.Random(20260917)
# Filled in by main(); the defaults are what a local stack gets.
OPTS = argparse.Namespace(invented=False, clubs=0, note=None, public_pages=True,
                          manifest=None, rounds=3, workers=16)
print_lock = threading.Lock()


def say(*parts):
    with print_lock:
        print(*parts, flush=True)


# ---------------------------------------------------------------------------
# HTTP


class ApiError(RuntimeError):
    def __init__(self, method, path, status, body):
        super().__init__(f"{method} {path} -> {status}: {body[:400]}")
        self.status = status
        self.body = body


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(6):
        req = urllib.request.Request(
            V1 + path, data=data, method=method,
            headers={"Content-Type": "application/json",
                     **({"Authorization": f"Bearer {token}"} if token else {})})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            # A ring behind a proxy answers 502/503 while it restarts, and a
            # restart is exactly what a burst of signups can cause.
            if e.code >= 500 and attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise ApiError(method, path, e.code, text) from None
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt < 5:
                time.sleep(2 ** attempt)
                continue
            raise


def rows(data):
    return data["items"] if isinstance(data, dict) and "items" in data else data


def psql(sql):
    return subprocess.run(
        ["docker", "exec", "-i", PG_CONTAINER, "psql", "-U", "fishers", "-d", "fishers", "-tAc", sql],
        capture_output=True, text=True, check=True).stdout.strip()


def parallel(fn, items, workers=12):
    with cf.ThreadPoolExecutor(max_workers=min(workers, OPTS.workers)) as pool:
        return list(pool.map(fn, items))


def iso(moment):
    return moment.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def london(day, hour, minute=0):
    return dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=LONDON)


# ---------------------------------------------------------------------------
# The area

HERTS = "Hertfordshire Saturday League"
MIDDX = "Middlesex Saturday League"
RING = "Chilterns & North London League"

# (name, short, area, league, ground, address, lat, lng, members, women's section)
CLUBS = [
    # Hemel Hempstead, Dacorum and St Albans
    ("Hemel Hempstead Town CC", "Hemel Hempstead Town", "Hemel Hempstead", HERTS,
     "Heath Park", "Heath Lane, Boxmoor, Hemel Hempstead HP1", 51.7488, -0.4730, 26, True),
    ("Boxmoor CC", "Boxmoor", "Hemel Hempstead", HERTS,
     "Blackbirds Moor", "Blackbirds Moor, Boxmoor, Hemel Hempstead HP1", 51.7452, -0.4852, 16, False),
    ("Leverstock Green CC", "Leverstock Green", "Hemel Hempstead", HERTS,
     "Pancake Lane", "Pancake Lane, Leverstock Green, Hemel Hempstead HP2", 51.7462, -0.4151, 16, True),
    ("Berkhamsted CC", "Berkhamsted", "Berkhamsted", HERTS,
     "Kitchener's Field", "Castle Hill, Berkhamsted HP4", 51.7667, -0.5597, 16, True),
    ("Tring Park CC", "Tring Park", "Tring", HERTS,
     "Pound Meadow", "Station Road, Tring HP23", 51.7965, -0.6553, 16, False),
    ("Kings Langley CC", "Kings Langley", "Kings Langley", HERTS,
     "Kings Langley", "Hempstead Road, Kings Langley WD4", 51.7142, -0.4583, 22, False),
    ("Chipperfield Cricketers CC", "Chipperfield", "Chipperfield", HERTS,
     "Chipperfield Common", "The Common, Chipperfield WD4", 51.7031, -0.4927, 16, False),
    ("Redbourn CC", "Redbourn", "Redbourn", HERTS,
     "Redbourn Common", "The Common, Redbourn AL3", 51.7985, -0.3930, 16, False),
    ("St Albans CC", "St Albans", "St Albans", HERTS,
     "Clarence Park", "Clarence Park, Hatfield Road, St Albans AL1", 51.7543, -0.3266, 16, True),
    # Watford, Three Rivers and Hertsmere
    ("Watford Town CC", "Watford Town", "Watford", HERTS,
     "Woodside Playing Fields", "Horseshoe Lane, Garston, Watford WD25", 51.6925, -0.3818, 24, True),
    ("Bushey CC", "Bushey", "Bushey", HERTS,
     "Bushey", "Bushey Hall Road, Bushey WD23", 51.6442, -0.3637, 16, False),
    ("Oxhey CC", "Oxhey", "Watford", HERTS,
     "Oxhey", "Oxhey, Watford WD19", 51.6402, -0.3868, 16, False),
    ("Croxley Guild CC", "Croxley Guild", "Croxley Green", HERTS,
     "Croxley Green", "The Green, Croxley Green WD3", 51.6468, -0.4455, 16, False),
    ("Rickmansworth CC", "Rickmansworth", "Rickmansworth", HERTS,
     "Rickmansworth", "Park Road, Rickmansworth WD3", 51.6395, -0.4702, 16, True),
    ("Sarratt CC", "Sarratt", "Sarratt", HERTS,
     "Sarratt Green", "The Green, Sarratt WD3", 51.6870, -0.4873, 16, False),
    ("Abbots Langley CC", "Abbots Langley", "Abbots Langley", HERTS,
     "Manor House Grounds", "High Street, Abbots Langley WD5", 51.7020, -0.4177, 16, False),
    ("Radlett CC", "Radlett", "Radlett", HERTS,
     "Cobden Hill", "Watling Street, Radlett WD7", 51.6851, -0.3175, 16, True),
    ("Chorleywood CC", "Chorleywood", "Chorleywood", HERTS,
     "Chorleywood Common", "Common Road, Chorleywood WD3", 51.6528, -0.5122, 16, False),
    # Harrow, Hillingdon and Brent
    ("Harrow Town CC", "Harrow Town", "Harrow", MIDDX,
     "Harrow", "Harrow HA2", 51.5808, -0.3509, 16, False),
    ("Harrow St Mary's CC", "Harrow St Mary's", "Harrow on the Hill", MIDDX,
     "Harrow on the Hill", "Harrow on the Hill HA1", 51.5731, -0.3372, 16, False),
    ("Pinner CC", "Pinner", "Pinner", MIDDX,
     "Montesole Playing Fields", "Montesole Playing Fields, Pinner HA5", 51.5942, -0.3845, 16, True),
    ("Stanmore CC", "Stanmore", "Stanmore", MIDDX,
     "Stanmore", "Uxbridge Road, Stanmore HA7", 51.6150, -0.3172, 16, True),
    ("Northwood CC", "Northwood", "Northwood", MIDDX,
     "Northwood", "Ducks Hill Road, Northwood HA6", 51.6112, -0.4378, 16, False),
    ("Eastcote CC", "Eastcote", "Eastcote", MIDDX,
     "Eastcote", "Eastcote Road, Eastcote HA5", 51.5780, -0.3960, 16, False),
    ("Wembley CC", "Wembley", "Wembley", MIDDX,
     "Vale Farm", "Watford Road, Sudbury, Wembley HA0", 51.5530, -0.3150, 16, False),
    ("Harefield CC", "Harefield", "Harefield", MIDDX,
     "Harefield", "Breakspear Road North, Harefield UB9", 51.6040, -0.4780, 16, False),
    # North London
    ("Hampstead CC", "Hampstead", "West Hampstead", MIDDX,
     "Lymington Road", "Lymington Road, West Hampstead NW6", 51.5510, -0.1882, 16, True),
    ("South Hampstead CC", "South Hampstead", "Brondesbury Park", MIDDX,
     "Milverton Road", "Milverton Road, Brondesbury Park NW6", 51.5418, -0.2140, 16, False),
    ("Brondesbury CC", "Brondesbury", "Queen's Park", MIDDX,
     "Harvist Road", "Harvist Road, Queen's Park NW6", 51.5353, -0.2080, 16, False),
    ("Finchley CC", "Finchley", "Finchley", MIDDX,
     "Arden Field", "East End Road, Finchley N3", 51.5998, -0.1850, 16, True),
    ("North Middlesex CC", "North Middlesex", "Crouch End", MIDDX,
     "Park Road", "Park Road, Crouch End N8", 51.5790, -0.1215, 16, True),
    ("Hornsey CC", "Hornsey", "Crouch End", MIDDX,
     "Tivoli Road", "Tivoli Road, Crouch End N8", 51.5845, -0.1262, 16, False),
    ("Southgate CC", "Southgate", "Southgate", MIDDX,
     "The Walker Ground", "Waterfall Road, Southgate N14", 51.6242, -0.1368, 16, False),
    ("Winchmore Hill CC", "Winchmore Hill", "Winchmore Hill", MIDDX,
     "The Paulin Ground", "Firs Lane, Winchmore Hill N21", 51.6308, -0.0943, 16, False),
    ("Enfield CC", "Enfield", "Enfield", MIDDX,
     "Enfield", "Enfield EN2", 51.6523, -0.0810, 16, False),
    ("Totteridge Millhillians CC", "Totteridge Millhillians", "Totteridge", MIDDX,
     "Totteridge", "Totteridge Lane, Totteridge N20", 51.6310, -0.1980, 16, False),
]

# Where people round each club come from, roughly. Weights, not quotas.
MIX = {
    RING: {"british": 45, "punjabi": 9, "gujarati": 13, "pakistani": 10, "tamil": 6,
           "sinhala": 4, "bangladeshi": 3, "afghan": 3, "southern": 4, "caribbean": 3},
    HERTS: {"british": 60, "punjabi": 8, "gujarati": 9, "pakistani": 9, "tamil": 3,
            "sinhala": 3, "bangladeshi": 2, "afghan": 2, "southern": 4},
    MIDDX: {"british": 36, "punjabi": 9, "gujarati": 17, "pakistani": 11, "tamil": 8,
            "sinhala": 6, "bangladeshi": 4, "afghan": 3, "southern": 3, "caribbean": 3},
}

FIRST = {
    "british": "James Tom Oliver Harry Jack George Charlie Sam Ben Joe Will Dan Luke Matt Chris Alex "
               "Rob Ed Josh Ryan Callum Jamie Lewis Adam Nick Mark Paul Steve Andy Richard Simon Pete "
               "Gareth Owen Rhys Connor Liam Sean Declan Fraser Rory Alfie Freddie Archie Toby Henry Max "
               "Ollie Jake Kieran Nathan Ross Scott Craig Stuart Graham Martin Neil Ian Dominic Hugo "
               "Barney Theo Elliot Joel Aaron Gavin Darren Lee Gary Kevin Tim Phil Jon Guy Seb Hamish Euan Niall",
    "punjabi": "Harpreet Gurpreet Jaspreet Manpreet Amandeep Harjit Kuldeep Jasvir Sukhdev Rajinder Ranjit "
               "Navdeep Karan Arjun Varun Ankit Vikram Sahil Gagan Parminder Tejinder Balraj Inderjit Jaskaran",
    "gujarati": "Nikhil Hardik Jay Kunal Mehul Nirav Pranav Rakesh Sanjay Hiren Dhruv Yash Parth Chirag "
                "Ketan Bhavin Jignesh Viral Kishan Rohan Aarav Dev Neel Rishi Vivek Ashwin Samir Tushar",
    "pakistani": "Imran Usman Bilal Hamza Asif Faisal Zubair Waqas Adeel Shoaib Saqib Kamran Umar Haris "
                 "Danyal Zain Rizwan Junaid Naveed Tariq Sajid Omar Ali Hassan Ibrahim Yasir Arslan Atif",
    "tamil": "Karthik Suresh Ganesh Prakash Arun Senthil Vignesh Rajesh Naveen Sriram Thusiyan Kajan "
             "Niroshan Mathan Pradeep Dinesh",
    "sinhala": "Kasun Dilshan Chamara Nuwan Lahiru Dhanushka Chathura Ruwan Sachith Tharindu Isuru Pasindu",
    "bangladeshi": "Rahim Tanvir Mehedi Nayeem Sabbir Rakib Fahim Sohel Arif Ashik Mizanur Jahid Imtiaz",
    "afghan": "Farid Najib Qais Zahir Ihsan Jawad Wahid Sediq Omid Hamid",
    "southern": "Pieter Riaan Francois Wian Hennie Jarrod Brodie Lachlan Hayden Cooper Blake Tane Ruan Dewald Jaco",
    "caribbean": "Andre Marlon Kemar Jermaine Shane Leon Nigel Carlton Desmond Everton Trevor Winston Delroy",
}
FIRST_WOMEN = {
    "british": "Sophie Emily Charlotte Hannah Lucy Grace Ellie Amy Megan Chloe Georgia Katie Rebecca Laura "
               "Holly Jess Freya Isla Rosie Abbie Beth Hollie Phoebe Millie Alice",
    "punjabi": "Simran Harleen Jasleen Navneet Amrit Manveer",
    "gujarati": "Priya Anjali Nisha Kiran Meera Riya Divya Shreya Pooja Reena",
    "pakistani": "Aisha Sana Zara Hira Nadia Ayesha Maryam Iqra",
    "tamil": "Divya Priya Kavya Nila Thanuja",
    "sinhala": "Sanduni Dilini Nimasha Hansika",
    "bangladeshi": "Nusrat Farzana Tahmina Sumaiya",
    "afghan": "Mariam Farah Laila",
    "southern": "Chloe Jess Megan Kayla",
    "caribbean": "Shanice Tanisha Kerry-Ann Aaliyah",
}
SURNAMES = {
    "british": "Smith Taylor Brown Wilson Evans Thomas Roberts Walker Wright Robinson Thompson White Hughes "
               "Edwards Green Hall Wood Harris Clarke Jackson Turner Hill Moore Cooper Ward Morris King Baker "
               "Harrison Morgan Allen Parker Price Bennett Carter Shaw Mills Fisher Barnes Hayes Cole Foster "
               "Holmes Lloyd Marshall Palmer Webb Rose Stevens Hunt Gibson Knight Pearce Reynolds Russell "
               "Ellis Fletcher Chapman Dixon Burton Lawrence Hart Gardner Sutton Doyle Murphy O'Brien Kelly "
               "Walsh Byrne McKenzie Campbell Stewart Murray Reid Fraser Davies Jones Williams Rees Powell "
               "Hopkins Newman Saunders Barker Stone Wells Hudson Lambert Bishop Bradley Hammond Holt "
               "Nicholls Osborne Kemp Tucker Goddard Lane Pryce Whitaker Ashworth Fenwick Rowley Dunn",
    "punjabi": "Sandhu Dhillon Gill Sidhu Grewal Bains Johal Sahota Bhatti Randhawa Atwal Virdi Chahal Kang "
               "Aujla Mann Sohal Toor Dhaliwal Hayer Khera Malhi Rai Bhogal Chana Ghuman Uppal",
    "gujarati": "Patel Shah Mehta Desai Joshi Parekh Thakkar Pandya Modi Vora Amin Bhatt Trivedi Chauhan "
                "Mistry Lakhani Kotecha Raval Soni Dave Vyas Rathod Solanki Chudasama Hirani Karia Popat",
    "pakistani": "Khan Ahmed Hussain Malik Iqbal Raza Chaudhry Butt Qureshi Mirza Sheikh Akhtar Javed Anwar "
                 "Aslam Rafiq Shah Abbasi Siddiqui Nawaz Mahmood Riaz Bashir Rashid",
    "tamil": "Raman Krishnan Subramaniam Rajan Natarajan Sivakumar Kumaran Venkatesan Iyer Pillai "
             "Sivapalan Thavarajah Nadarajah Yogarajah",
    "sinhala": "Perera Fernando De_Silva Wickramasinghe Gunawardena Dissanayake Bandara Herath Ratnayake "
               "Jayawardena Kumara Rodrigo",
    "bangladeshi": "Rahman Hossain Islam Uddin Chowdhury Miah Alam Karim Haque",
    "afghan": "Safi Noori Hotak Popal Karimi Wardak Sultani Rahimi Hakimi",
    "southern": "Botha Pretorius Venter du_Toit Kruger Fourie Coetzee Visser Joubert Swanepoel Mackay "
                "Holloway Pritchard Whitmore Kennedy Sutherland Ngata Tipene Brink Nel",
    "caribbean": "Francis Joseph Charles Gordon Bailey Forde Morrison Henry Pinnock Beckford Spence Grant",
}
# Names that already belong to somebody people have heard of. A fixture list
# full of invented players should not hand anyone a famous one by accident.
FAMOUS = {n.lower() for n in """
Jack Hobbs|Mark Wood|Dan Lawrence|Ollie Robinson|Jamie Smith|Ben Foster|James Taylor|Chris Jordan|
Tom Moore|Luke Wright|Mark Taylor|Nick Knight|Simon Jones|Jack Russell|Craig White|Ed Smith|
Tom Harrison|Richard Thompson|Ian Ward|Will Smith|Paul Walker|Chris Evans|Richard Hammond|Joe Hart|
Scott Parker|Ben White|Luke Shaw|Joe Allen|Andy Murray|Jamie Murray|Mark Williams|Mark Allen|
Ian Wright|James Martin|Tom Curran|Sam Curran|Luke Wood|Harry Brook|Joe Root|Ben Stokes|
Hardik Pandya|Jay Shah|Dev Patel|Nirav Modi|Sriram Krishnan|Kiran Desai|Imran Khan|Shoaib Akhtar|
Shoaib Malik|Saqib Mahmood|Shoaib Bashir|Faisal Iqbal|Asif Ali|Yasir Shah|Junaid Khan|Sajid Khan|
Hassan Ali|Zain Malik|Sabbir Rahman|Mizanur Rahman|Tanvir Islam|Lahiru Kumara|Trevor Francis|
Delroy Grant|Leon Bailey|Trevor Bailey|Jermaine Beckford|Kemar Bailey|Amy Jones|Charlotte Edwards|
Freya Davies|Sophie Turner|Katie Price|Chloe Kelly|Alice Evans|Grace Harris|Hollie Doyle|
Laura Wright|Maryam Nawaz|Nadia Hussain|Sana Khan|Ali Khan|Imran Hussain|Adam Hughes|Tom Jones|
Matt Hancock|George Osborne|Rishi Shah|Steve Davis|Andy Flower|Graham Thorpe|Gareth Thomas|
Owen Farrell|Joe Marler|Jack Nowell|Sam Warburton|Hamza Choudhury|Rob Key|Chris Woakes|Nick Pope|
Jonny Bairstow|Ollie Pope|Paul Taylor|Neil Robertson|Steve James|Sam Allardyce|Harry Kane|Theo Walcott
""".replace("\n", "").split("|")}

# For a shared server. Invented clubs in the same towns: a real club's name on
# a page of invented players and invented results is not ours to put there.
RING_CLUBS = [
    ("Gade Valley CC", "Gade Valley", "Hemel Hempstead", RING,
     "Gadebridge Park", "Gadebridge Park, Hemel Hempstead HP1", 51.7620, -0.4760, 26, True),
    ("Boxmoor Wanderers CC", "Boxmoor Wanderers", "Hemel Hempstead", RING,
     "Moor Lane", "Moor Lane, Boxmoor, Hemel Hempstead HP1", 51.7440, -0.4880, 24, False),
    ("Bulbourne CC", "Bulbourne", "Berkhamsted", RING,
     "Bulbourne Meadow", "Lower Kings Road, Berkhamsted HP4", 51.7640, -0.5640, 22, False),
    ("Colne Valley Ramblers CC", "Colne Valley", "Watford", RING,
     "Riverside Fields", "Riverside, Watford WD17", 51.6600, -0.4000, 16, True),
    ("Oxhey Park CC", "Oxhey Park", "Watford", RING,
     "Oxhey Park", "Eastbury Road, Oxhey, Watford WD19", 51.6420, -0.3900, 16, False),
    ("Chess Valley CC", "Chess Valley", "Rickmansworth", RING,
     "Mill Meadow", "Mill End, Rickmansworth WD3", 51.6450, -0.4850, 16, False),
    ("Harrow Weald Wanderers CC", "Harrow Weald", "Harrow", RING,
     "Weald Common", "Harrow Weald HA3", 51.6040, -0.3350, 16, False),
    ("Pinner Vale CC", "Pinner Vale", "Pinner", RING,
     "Vale Field", "Pinner HA5", 51.5930, -0.3900, 16, True),
    ("Welsh Harp CC", "Welsh Harp", "Wembley", RING,
     "Reservoir Fields", "Birchen Grove, Wembley NW9", 51.5700, -0.2470, 16, False),
    ("Crouch Hill CC", "Crouch Hill", "Crouch End", RING,
     "Hillside Ground", "Crouch Hill, London N8", 51.5760, -0.1220, 16, True),
    ("Enfield Chase Nomads CC", "Enfield Chase", "Enfield", RING,
     "Chase Meadow", "Enfield EN2", 51.6560, -0.0900, 16, False),
    ("Totteridge Common CC", "Totteridge Common", "Totteridge", RING,
     "The Common", "Totteridge Common, London N20", 51.6330, -0.1990, 16, False),
]

# A club side, top to bottom: (position, bowling styles to pick from).
SIDE = [
    ("Batter", ["Doesn't bowl"]),
    ("Batter", ["Doesn't bowl", "Right-arm medium"]),
    ("Batter", ["Off-spin", "Doesn't bowl"]),
    ("Batter", ["Doesn't bowl", "Leg-spin"]),
    ("All-rounder", ["Right-arm medium", "Off-spin"]),
    ("Wicketkeeper", ["Doesn't bowl"]),
    ("All-rounder", ["Left-arm orthodox", "Right-arm medium", "Left-arm seam"]),
    ("Spinner", ["Off-spin", "Leg-spin", "Left-arm orthodox"]),
    ("Fast Bowler", ["Right-arm fast", "Right-arm medium"]),
    ("Fast Bowler", ["Right-arm fast", "Left-arm seam"]),
    ("Fast Bowler", ["Right-arm medium", "Right-arm fast"]),
]
SPARE = [
    ("Batter", ["Doesn't bowl", "Off-spin"]),
    ("All-rounder", ["Right-arm medium", "Leg-spin"]),
    ("Fast Bowler", ["Right-arm medium", "Left-arm seam"]),
    ("Wicketkeeper", ["Doesn't bowl"]),
    ("Spinner", ["Off-spin", "Left-arm orthodox"]),
]
# Where a squad player usually bats.
SPARE_ORDER = {"Batter": 3, "All-rounder": 6, "Wicketkeeper": 7, "Spinner": 9, "Fast Bowler": 10}
TRANSPORT = ["driverWithSeats", "driver", "driver", "publicTransport", "needsLift"]
DIVISIONS = ["premier", "division1", "division2", "division3", "division4", "division5"]
UMPIRES: list[str] = []


class Person:
    def __init__(self, name, background, woman=False):
        self.name = name
        self.background = background
        self.woman = woman
        self.email = re.sub(r"[^a-z.\-]", "", name.lower().replace(" ", ".")) + "@fishers.test"
        self.id = None
        self.club = None
        self.position = "Batter"
        self.bowling = "Doesn't bowl"
        self.bats_left = False
        self.order = 11
        self.age_group = "senior"
        self.tier = "club"
        self.division = "division3"
        self.role_intent = "player"
        self._token = None
        self._refresh = None
        self._at = 0.0
        self._lock = threading.Lock()

    @property
    def first(self):
        return self.name.split(" ")[0]

    @property
    def bowls(self):
        return self.bowling != "Doesn't bowl"

    def token(self):
        """Signed in once; refreshed after that. A password check costs the
        server a real slice of CPU, and seven hundred of them twice over is
        most of a run."""
        with self._lock:
            if self._token is None:
                try:
                    auth = call("POST", "/auth/login", {"identifier": self.email, "password": PASSWORD})
                except ApiError as e:
                    if e.status not in (400, 401, 404):
                        raise
                    auth = call("POST", "/auth/signup",
                                {"name": self.name, "email": self.email, "password": PASSWORD})
            elif time.time() - self._at > 600:
                auth = call("POST", "/auth/refresh", {"refresh_token": self._refresh})
            else:
                return self._token
            self._token = auth["access_token"]
            self._refresh = auth["refresh_token"]
            self.id = auth["user"]["id"]
            self._at = time.time()
            return self._token

    def player(self):
        return {"id": self.id, "name": self.name, "bats_left": self.bats_left}


taken_names: set[str] = set()


def invent(league, woman=False, family=None):
    """A name nobody else has. `family` counts surnames already in the club:
    brothers and cousins play together, but not three of them in a squad."""
    mix = MIX[league]
    for _ in range(400):
        bg = rng.choices(list(mix), weights=list(mix.values()))[0]
        firsts = (FIRST_WOMEN if woman else FIRST)[bg].split()
        surname = rng.choice(SURNAMES[bg].split()).replace("_", " ")
        name = f"{rng.choice(firsts)} {surname}"
        if name.lower() in FAMOUS or name in taken_names:
            continue
        if family is not None:
            if family.get(surname, 0) >= 2:
                continue
            family[surname] = family.get(surname, 0) + 1
        taken_names.add(name)
        return Person(name, bg, woman)
    raise SystemExit(f"ran out of names for {league}")


class Club:
    def __init__(self, spec):
        (self.name, self.short, self.town, self.league, self.ground, self.address,
         self.lat, self.lng, self.size, self.women) = spec
        self.slug = re.sub(r"[^a-z0-9]+", "-", self.short.lower()).strip("-")
        self.id = None
        self.venue_id = None
        self.teams: dict[str, str] = {}
        self.men: list[Person] = []
        self.women_squad: list[Person] = []
        self.secretary: Person | None = None
        self.captain: Person | None = None
        self.vice: Person | None = None
        self.second_captain: Person | None = None

    def first_xi(self, week=0):
        """The regular side in batting order, with the odd change a Saturday
        brings. A replacement bats where the player they replace would have."""
        side = list(self.men[:11])
        spares = self.men[11:16]
        r = random.Random(f"{self.slug}-{week}")
        for _ in range(r.choice([0, 1, 1, 2])):
            out = r.choice([p for p in side if p is not self.captain and p.position != "Wicketkeeper"])
            same = [p for p in spares if p.position == out.position and p not in side] \
                or [p for p in spares if p not in side and p.position != "Wicketkeeper"]
            if same:
                side[side.index(out)] = r.choice(same)
        return side

    def second_xi(self):
        return self.men[11:22]

    def captain_of(self, xi):
        for p in (self.captain, self.second_captain, self.vice):
            if p in xi:
                return p
        return xi[4]


def chosen_clubs():
    """The area's clubs, or invented ones for a shared server. An odd club
    would sit out every round, so the count is always even."""
    specs = RING_CLUBS if OPTS.invented else CLUBS
    if OPTS.clubs:
        per_league: dict[str, list] = {}
        for spec in specs:
            per_league.setdefault(spec[3], []).append(spec)
        wanted, specs = OPTS.clubs, []
        for league, group in per_league.items():
            take = max(2, round(wanted * len(group) / sum(len(g) for g in per_league.values())))
            specs += group[: take - take % 2]
    return specs


def build_world():
    clubs = [Club(spec) for spec in chosen_clubs()]
    for club in clubs:
        shape = SIDE + SPARE
        if club.size > 16:
            shape = SIDE + SIDE + SPARE[: club.size - 22]
        family: dict[str, int] = {}
        for index, (position, styles) in enumerate(shape[: club.size]):
            p = invent(club.league, family=family)
            p.club = club
            p.position = position
            p.bowling = rng.choice(styles)
            p.bats_left = rng.random() < 0.2
            p.order = SPARE_ORDER[position] if index >= 22 or (club.size <= 16 and index >= 11) \
                else (index % 11) + 1
            first_team = index < 11
            p.tier = rng.choice(["club", "advanced"] if first_team else ["intermediate", "club", "improver"])
            p.division = rng.choice(DIVISIONS[1:4] if first_team else DIVISIONS[3:])
            p.age_group = "vets40" if rng.random() < 0.18 else "senior"
            club.men.append(p)
        if club.women:
            for position, styles in SIDE[:6]:
                p = invent(club.league, woman=True, family=family)
                p.club = club
                p.position = position
                p.bowling = rng.choice(styles)
                p.bats_left = rng.random() < 0.15
                p.tier = rng.choice(["intermediate", "club"])
                p.division = "development"
                club.women_squad.append(p)
        # The all-rounder at five captains. Hemel's captain runs the club as
        # well, so one account sees everything a secretary does.
        club.captain = club.men[4]
        club.vice = club.men[7]
        if len(club.men) > 16:
            club.second_captain = club.men[13]
        if club.name == "Hemel Hempstead Town CC":
            club.secretary = club.captain
        else:
            club.secretary = invent(club.league, family=family)
            club.secretary.club = club
            club.secretary.age_group = "vets50" if rng.random() < 0.5 else "vets40"
            club.secretary.tier = "intermediate"
            club.secretary.division = "social"
        club.secretary.role_intent = "secretary"
    # League umpires: named on the card, never signed up.
    for league in (HERTS, MIDDX):
        UMPIRES.extend(invent(league).name for _ in range(15))
    return clubs


# ---------------------------------------------------------------------------
# Accounts, clubs, squads


def profile_body(p: Person):
    club = p.club
    postcode = club.address.split()[-1]
    return {
        "primary_sport": "cricket",
        "sports_played": ["cricket"],
        "position_role": p.position,
        "skill_level": p.tier,
        "role_intent": p.role_intent,
        "sport_profiles": [{
            "sport": "cricket",
            "position": p.position,
            "skill_level": p.tier,
            "current_division": p.division,
            "target_division": DIVISIONS[max(0, DIVISIONS.index(p.division) - 1)]
            if p.division in DIVISIONS else "division5",
            "age_group": p.age_group,
            "team_name": f"{club.short} {'Women' if p.woman else '1st XI' if p in club.men[:11] else '2nd XI'}",
            "years_playing": rng.randint(3, 28) if p.age_group == "senior" else rng.randint(20, 40),
            "stats": {
                "batting_style": "Left-hand" if p.bats_left else "Right-hand",
                "bowling_style": p.bowling,
                "batting_number": str(p.order),
            },
        }],
        "location": {
            "area": club.town,
            "postcode": postcode,
            "travel_radius_miles": rng.choice([5, 10, 10, 15, 20, 25]),
            "transport": rng.choice(TRANSPORT),
            "spare_seats": rng.choice([0, 1, 2, 3]),
            "preferred_days": [7] if rng.random() < 0.6 else [7, 1],
        },
    }


def sign_everyone_up(people):
    parallel(lambda p: p.token(), people, workers=16)
    # Only where the server asks for a code, and only where the database is
    # this machine's: a ring with verification off needs none of this.
    if call("GET", "/me/verification", None, people[0].token()).get("enabled"):
        try:
            psql("UPDATE users SET email_verified_at = now() "
                 "WHERE email LIKE '%@fishers.test' AND email_verified_at IS NULL")
        except (subprocess.CalledProcessError, FileNotFoundError):
            say("  ! this server asks for a confirmation code and its database is not local — "
                "clubs may be refused. Mark the seeded addresses confirmed yourself.")
    bodies = [(p, profile_body(p)) for p in people]
    parallel(lambda pb: call("PATCH", "/me", pb[1], pb[0].token()), bodies, workers=16)


def set_up_club(club: Club):
    sec = club.secretary
    tok = sec.token()
    mine = {c["name"]: c for c in rows(call("GET", "/me/clubs", None, tok))}
    if club.name in mine:
        club.id = mine[club.name].get("id") or mine[club.name].get("club_id")
    else:
        description = f"Saturday league, Sunday friendlies and midweek nets in {club.town}."
        club.id = call("POST", "/clubs", {
            "name": club.name, "sport_types": ["cricket"], "visibility": "public",
            "description": f"{description} {OPTS.note}".strip() if OPTS.note else description}, tok)["id"]

    icon = club.captain
    call("PATCH", f"/clubs/{club.id}/page", {
        "slug": club.slug, "public_page": OPTS.public_pages,
        "tagline": f"{club.league.replace(' Saturday League', '')} cricket at {club.ground}",
        "about": (f"{club.short} play Saturday league cricket in the {club.league}, with a Sunday XI, "
                  f"midweek nets through the summer and indoor nets in the winter"
                  f"{', and a women' + chr(39) + 's softball section' if club.women else ''}. "
                  f"New players of every standard are welcome — come to nets first."
                  + (f" {OPTS.note}" if OPTS.note else "")),
        "ground": club.ground,
        "contact_email": f"secretary@{club.slug}.fishers.test",
    }, tok)

    venues = rows(call("GET", f"/clubs/{club.id}/venues", None, tok))
    venue = next((v for v in venues if v["name"] == club.ground), None) or call(
        "POST", f"/clubs/{club.id}/venues",
        {"name": club.ground, "address": club.address, "lat": club.lat, "lng": club.lng}, tok)
    club.venue_id = venue["id"]

    team_names = ["1st XI", "2nd XI", "Sunday XI"] + (["Women's XI"] if club.women else [])
    have = {t["name"]: t["id"] for t in rows(call("GET", f"/clubs/{club.id}/teams", None, tok))}
    for name in team_names:
        club.teams[name] = have.get(name) or call(
            "POST", f"/clubs/{club.id}/teams", {"name": name, "sport": "cricket"}, tok)["id"]

    for p in club.men + club.women_squad:
        if p is sec:
            continue
        call("POST", f"/clubs/{club.id}/members", {"user_id": p.id, "role": "member"}, tok)
    call("PATCH", f"/clubs/{club.id}/members/{club.captain.id}",
         {"role": "club_admin" if club.captain is sec else "team_captain", "captain": True}, tok)
    call("PATCH", f"/clubs/{club.id}/members/{club.vice.id}", {"role": "team_vice_captain"}, tok)
    if club.second_captain:
        call("PATCH", f"/clubs/{club.id}/members/{club.second_captain.id}", {"role": "team_captain"}, tok)
    call("PATCH", f"/clubs/{club.id}/page", {"icon_player_id": icon.id}, tok)

    def team(name, people):
        existing = {m.get("user_id") for m in rows(call("GET", f"/teams/{club.teams[name]}/members", None, tok))}
        for p in people:
            if p.id not in existing:
                call("POST", f"/teams/{club.teams[name]}/members", {"user_id": p.id}, tok)

    team("1st XI", club.men[:11])
    team("2nd XI", club.men[11:22] or club.men[11:])
    team("Sunday XI", club.men[5:16:2] + [sec])
    if club.women:
        team("Women's XI", club.women_squad)
    say(f"  {club.name:<28} {len(club.men) + len(club.women_squad):>2} players · {club.ground}")


# ---------------------------------------------------------------------------
# Cricket, ball by ball

CONDITIONS = {"ground": "open", "ball": "white", "fielders_outside_powerplay": 2,
              "fielders_outside_normal": 5, "fielders_behind_square_leg": 2}

# Where each stroke goes for a right-hander; 0 is straight, clockwise.
SHOT_ANGLES = {
    "drive": [(285, 345), (10, 40)], "loft": [(330, 359), (0, 35)], "cut": [(230, 280)],
    "pull": [(60, 130)], "hook": [(110, 160)], "sweep": [(95, 150)], "glance": [(140, 178)],
    "flick": [(45, 100)], "edge": [(182, 222)],
}
SHOTS_FOR = {
    1: ["drive", "flick", "glance", "cut", "pull", "edge"], 2: ["drive", "cut", "pull", "flick", "sweep"],
    3: ["drive", "cut", "pull"], 4: ["drive", "cut", "pull", "sweep", "flick", "glance", "edge"],
    6: ["loft", "pull", "sweep", "hook", "loft"],
}


def shot(runs, left, r):
    kind = r.choice(SHOTS_FOR[runs])
    lo, hi = r.choice(SHOT_ANGLES[kind])
    angle = r.randint(lo, hi) % 360
    if left:
        angle = (360 - angle) % 360
    reach = 1.0 if runs >= 4 else round(r.uniform(0.35, 0.8), 2)
    return {"angle": angle, "kind": kind, "reach": reach}


class Match:
    """One match's log, posted a few balls at a time and read back from the engine.

    The engine decides who is on strike, when an over and an innings are done,
    and when the chase is won, so the simulation asks it after anything that
    could change those rather than keeping its own copy of the Laws.
    """

    def __init__(self, match_id, scorer: Person, clock, pace, r):
        self.id = match_id
        self.scorer = scorer
        self.clock = clock
        self.pace = pace
        self.r = r
        self.pending = []
        found = call("GET", f"/cricket/matches/{match_id}", None, scorer.token())
        self.seq = found.get("last_seq", 0)
        self.state = found["state"]

    def ev(self, kind, seconds=None):
        self.seq += 1
        self.clock += dt.timedelta(seconds=self.pace if seconds is None else seconds)
        self.pending.append({"client_event_id": str(uuid.uuid4()), "seq": self.seq,
                             "kind": kind, "at": iso(self.clock)})

    def flush(self):
        if self.pending:
            body = {"device_id": "seed-area", "events": self.pending}
            self.state = call("POST", f"/cricket/matches/{self.id}/events", body, self.scorer.token())["state"]
            self.pending = []
        return self.state

    @property
    def finished(self):
        return self.state["status"] in ("complete", "published")

    def innings_over(self, index):
        return self.finished or self.state["innings"][index]["complete"]


def pending_runs(kind):
    if kind["type"] == "delivery_recorded":
        return kind["runs"]
    if kind["type"] == "extras_recorded":
        return kind["runs"] + (1 if kind["kind"] in ("wide", "no_ball") else 0)
    return 0


def next_bowler(bowlers, history, cap, overs_left, r):
    """Two ends, spells of four to six overs, the openers back at the death."""
    last = history[-1]
    other_end = history[-2] if len(history) > 1 else None
    count = {b.id: history.count(b.id) for b in bowlers}
    can = [b for b in bowlers if b.id != last and count[b.id] < cap]
    if not can:
        can = [b for b in bowlers if b.id != last]
    spell = 0
    for bowler_id in reversed(history[-2::-2] if len(history) > 1 else []):
        spell = spell + 1 if bowler_id == other_end else 0
    by_id = {b.id: b for b in can}
    if other_end in by_id and spell < r.choice([4, 5, 6]):
        return by_id[other_end]
    if overs_left <= 5:
        return max(can, key=lambda b: (cap - count[b.id], -bowlers.index(b)))
    rested = [b for b in can if b.id != other_end]
    fresh = [b for b in rested if count[b.id] == 0]
    return (fresh or rested or can)[0]


def play_innings(m: Match, index, batting, bat_xi, bowl_xi, keeper, overs, stop_at_balls=None):
    r = m.r
    by_id = {p.id: p for p in bat_xi + bowl_xi}
    rank = {"Fast Bowler": 0, "Spinner": 1, "All-rounder": 2}
    bowlers = sorted([p for p in bowl_xi if p.bowls], key=lambda p: (rank.get(p.position, 3), p.order))
    if len(bowlers) < 5:
        bowlers += [p for p in bowl_xi if p not in bowlers and p is not keeper][: 5 - len(bowlers)]
    cap = max(1, -(-overs // 5))
    history = [bowlers[0].id]
    m.ev({"type": "innings_started", "innings_index": index, "batting": batting,
          "striker_id": bat_xi[0].id, "non_striker_id": bat_xi[1].id,
          "bowler_id": bowlers[0].id, "super_over": False}, seconds=1500 if index else 120)
    m.flush()
    balls = 0
    free_hit = False
    for over in range(overs):
        if m.innings_over(index):
            break
        if over:
            bowler = next_bowler(bowlers, history, cap, overs - over, r)
            history.append(bowler.id)
            m.ev({"type": "bowler_changed", "bowler_id": bowler.id}, seconds=45)
        bowler = by_id[history[-1]]
        spinner = bowler.position == "Spinner" or "spin" in bowler.bowling or "orthodox" in bowler.bowling
        death = over >= overs - 5
        legal = 0
        while legal < 6:
            if stop_at_balls is not None and balls >= stop_at_balls:
                return m.flush()
            target = m.state.get("target")
            if index == 1 and target and \
                    m.state["innings"][1]["runs"] + sum(pending_runs(e["kind"]) for e in m.pending) >= target:
                return m.flush()

            roll = r.random()
            if roll < 0.035:
                m.ev({"type": "extras_recorded", "kind": "wide", "runs": 0, "boundary": False,
                      "off_the_bat": False, "shot": None})
                continue
            if roll < 0.043:
                m.ev({"type": "extras_recorded", "kind": "no_ball", "runs": 0, "boundary": False,
                      "off_the_bat": True, "shot": None})
                free_hit = True
                continue
            legal += 1
            balls += 1
            if roll < 0.057:
                # A leg bye or a bye run: the batters have crossed.
                m.ev({"type": "extras_recorded", "kind": r.choice(["leg_bye", "leg_bye", "bye"]),
                      "runs": 1, "boundary": False, "off_the_bat": False, "shot": None})
                free_hit = False
                m.flush()
                if m.innings_over(index):
                    break
                continue

            weights = [0.40, 0.30, 0.09, 0.012, 0.10, 0.045, 0.053] if death \
                else [0.515, 0.27, 0.075, 0.012, 0.07, 0.018, 0.04]   # 0 1 2 3 4 6 W
            if bowler.position not in rank:
                weights[4] *= 1.3
                weights[6] *= 0.8
            outcome = r.choices([0, 1, 2, 3, 4, 6, "W"], weights=weights)[0]
            if outcome == "W" and free_hit:
                outcome = 0
            free_hit = False

            if outcome != "W":
                # Strike only changes on odd runs or at the end of an over, and
                # both flush, so the engine's striker is still the one facing.
                striker = by_id[m.state["innings"][index]["striker_id"]]
                m.ev({"type": "delivery_recorded", "runs": outcome, "is_legal": True,
                      "is_boundary_four": outcome == 4, "is_boundary_six": outcome == 6,
                      "shot": shot(outcome, striker.bats_left, r) if outcome else None})
                if outcome in (1, 3) or legal == 6:
                    m.flush()
                    if m.innings_over(index):
                        break
                continue

            m.flush()
            inn = m.state["innings"][index]
            # The card lists the whole XI from the first ball, so "has batted"
            # is out, has faced, or is standing there now.
            batted = {b["player_id"] for b in inn["batters"] if b["out"] or b["balls"] or b["retired_hurt"]}
            batted |= {inn["striker_id"], inn["non_striker_id"]}
            coming_in = next((p for p in bat_xi if p.id not in batted), None)
            last_wicket = inn["wickets"] + 1 >= inn["wickets_allowed"] or coming_in is None
            kind = r.choices(["caught", "bowled", "lbw", "run_out", "stumped"],
                             weights=[50, 22, 14, 7, 7 if spinner and keeper else 0])[0]
            fielders = [p for p in bowl_xi if p is not bowler]
            fielder = None
            if kind == "caught":
                pick = r.random()
                fielder = bowler if pick < 0.07 else keeper if keeper and pick < 0.28 else r.choice(fielders)
            elif kind == "stumped":
                fielder = keeper
            elif kind == "run_out":
                fielder = r.choice(fielders)
            m.ev({"type": "wicket_recorded", "batter_id": inn["striker_id"], "kind": kind,
                  "fielder_id": fielder.id if fielder else None,
                  "new_batter_id": None if last_wicket else coming_in.id,
                  "runs": 0, "on_extra": False}, seconds=150)
            m.flush()
            if m.innings_over(index):
                break
        m.flush()
    return m.flush()


def prepare_match(m: Match, home: Club, away: Club, home_xi, away_xi, overs, umpires, home_name, away_name):
    r = m.r
    conditions = dict(CONDITIONS, overs_limit=overs, overs_per_bowler=max(1, -(-overs // 5)),
                      powerplay_overs=0 if overs >= 40 else min(6, overs // 3),
                      target_overs_per_hour=0 if overs >= 40 else 14)
    keeper = lambda xi: next((p.id for p in xi if p.position == "Wicketkeeper"), None)
    m.ev({"type": "match_prepared", "overs_limit": overs, "home_name": home_name, "away_name": away_name}, 0)
    m.ev({"type": "conditions_proposed", "by": "home", "by_name": home.captain_of(home_xi).name,
          "conditions": conditions})
    m.ev({"type": "conditions_agreed", "side": "away", "captain_name": away.captain_of(away_xi).name})
    if umpires:
        m.ev({"type": "officials_appointed", "officials": {
            "umpires": [{"id": str(uuid.uuid5(uuid.NAMESPACE_DNS, u + ".umpire.fishers.test")),
                         "name": u, "bats_left": False} for u in umpires],
            "scorers": []}})
    winner = r.choice(["home", "away"])
    decision = r.choice(["bat", "bowl"])
    m.ev({"type": "toss_recorded", "winner": winner, "decision": decision}, 300)
    m.ev({"type": "xi_selected", "side": "home", "players": [p.player() for p in home_xi],
          "captain_id": home.captain_of(home_xi).id, "keeper_id": keeper(home_xi)})
    m.ev({"type": "xi_selected", "side": "away", "players": [p.player() for p in away_xi],
          "captain_id": away.captain_of(away_xi).id, "keeper_id": keeper(away_xi)})
    m.flush()
    return winner if decision == "bat" else ("away" if winner == "home" else "home")


def play_match(fx, stop_second_innings_at=None):
    home, away = fx["home"], fx["away"]
    overs = fx["overs"]
    scorer = fx.get("scorer") or home.secretary
    r = random.Random(fx["event_id"])
    home_name, away_name = fx.get("home_name", home.short), fx.get("away_name", away.short)
    match = call("POST", f"/events/{fx['event_id']}/cricket-match",
                 {"overs_limit": overs, "home_name": home_name, "away_name": away_name}, scorer.token())
    call("POST", f"/cricket/matches/{match['id']}/claim-scorer", {"device_id": "seed-area"}, scorer.token())
    m = Match(match["id"], scorer, fx["start"], 40 if overs >= 40 else 30, r)
    fx["match_id"] = match["id"]
    if m.seq > 0:
        return m.state   # played on an earlier run
    umpires = r.sample(UMPIRES, 2) if overs >= 40 else []
    first = prepare_match(m, home, away, fx["home_xi"], fx["away_xi"], overs, umpires, home_name, away_name)
    second = "away" if first == "home" else "home"
    xi = {"home": fx["home_xi"], "away": fx["away_xi"]}
    keeper = lambda side: next((p for p in xi[side] if p.position == "Wicketkeeper"), None)
    play_innings(m, 0, first, xi[first], xi[second], keeper(second), overs)
    play_innings(m, 1, second, xi[second], xi[first], keeper(first), overs, stop_second_innings_at)
    if m.finished:
        best = best_player(m.state)
        if best:
            m.ev({"type": "player_of_the_match", "player_id": best}, 600)
            m.flush()
    return m.state


def best_player(state):
    """Runs, and a wicket worth about twenty of them."""
    score: dict[str, float] = {}
    for inn in state["innings"]:
        for b in inn["batters"]:
            score[b["player_id"]] = score.get(b["player_id"], 0) + b["runs"]
        for b in inn["bowlers"]:
            score[b["player_id"]] = score.get(b["player_id"], 0) + 22 * b["wickets"] - 0.3 * b["runs"]
    return max(score, key=score.get) if score else None


# ---------------------------------------------------------------------------
# The calendar


def round_robin(clubs):
    """The circle method: every club once per round, nobody twice. Home and
    away swap round by round, or the club the circle turns on never travels."""
    teams = list(clubs)
    rounds = []
    for number in range(len(teams) - 1):
        pairs = [(teams[i], teams[-1 - i]) if (number + i) % 2 == 0 else (teams[-1 - i], teams[i])
                 for i in range(len(teams) // 2)]
        rounds.append(pairs)
        teams = [teams[0]] + [teams[-1]] + teams[1:-1]
    return rounds


def find_or_create_event(club: Club, title, body, tok=None):
    """Matched on title and start, so a weekly fixture is one event per week."""
    tok = tok or club.secretary.token()
    start = body["start_at"]
    query = f"/events?club_id={club.id}&q={urllib.parse.quote(title)}&per_page=100"
    for event in rows(call("GET", query, None, tok)):
        if event["title"] == title and \
                dt.datetime.fromisoformat(event["start_at"].replace("Z", "+00:00")) == \
                dt.datetime.fromisoformat(start.replace("Z", "+00:00")):
            return event, False
    return call("POST", "/events", dict(body, club_id=club.id, sport="cricket", title=title), tok), True


def league_fixture(home: Club, away: Club, day, round_no):
    start = london(day, 13, 0)
    event, _ = find_or_create_event(home, f"{home.short} v {away.short}", {
        "event_subtype": "league_match", "opponent_club_id": away.id, "team_id": home.teams["1st XI"],
        "venue_id": home.venue_id, "start_at": iso(start), "end_at": iso(start + dt.timedelta(hours=7)),
        "capacity": 13, "fee_amount_cents": 1200,
        "metadata": {"opposition": away.short, "home_name": home.short,
                     "competition": f"{home.league}, round {round_no}"}})
    return {"home": home, "away": away, "event_id": event["id"], "start": start, "overs": 40,
            "home_xi": home.first_xi(round_no), "away_xi": away.first_xi(round_no)}


def mark_availability(club: Club, saturdays):
    def one(p: Person):
        r = random.Random(f"avail-{p.email}")
        for day in saturdays:
            status = r.choices(["available", "maybe", "unavailable"], weights=[72, 12, 16])[0]
            call("POST", "/availability/bulk", {"dates": [day.isoformat()], "status": status}, p.token())
    parallel(one, club.men, workers=6)


def rsvp(event_id, people, weights=(78, 12, 10), seed=""):
    def one(p: Person):
        r = random.Random(f"rsvp-{seed}-{p.email}")
        status = r.choices(["going", "maybe", "not_going"], weights=weights)[0]
        call("POST", f"/events/{event_id}/rsvp", {"status": status}, p.token())
    parallel(one, people, workers=8)


CHAT = [
    "{first} here — who's around for nets on Tuesday? I'll bring the bowling machine key.",
    "Available Saturday. Can give two people a lift from {town} station if needed.",
    "Teas this week are on the rota for {first2}'s family 🙌",
    "Great win last week, fielding was sharp. Let's keep that going.",
    "Anyone got a spare pair of pads size M? Mine have finally given up.",
    "Ground's had a good cut — looks a belter for Saturday.",
    "Match fees for last Saturday please — £12 by bank transfer, reference your surname.",
    "Can't make Saturday unfortunately, wedding in the family. Sunday XI I'm in.",
    "Heavy roller's back from repair, so no excuses for the pitch now 😂",
    "Reminder: end-of-season dinner tickets are up in the app. Numbers to the bar by Friday.",
    "Who's got the scorebook? Left it in the pavilion after the T20.",
    "Nets moving indoors from October — Friday nights, details to follow.",
]


def club_chat(club: Club):
    tok = club.secretary.token()
    title = f"{club.short} — club chat"
    if any(t.get("title") == title for t in rows(call("GET", "/conversations", None, tok))):
        return
    convo = call("POST", "/conversations", {"title": title, "club_id": club.id}, tok)
    r = random.Random(f"chat-{club.slug}")
    for line, poster in zip(r.sample(CHAT, 7), r.sample(club.men + club.women_squad, 7)):
        text = line.format(first=poster.first, first2=r.choice(club.men).first, town=club.town)
        call("POST", f"/conversations/{convo['id']}/messages", {"body": text}, poster.token())


SHOP = [
    ("Club cap", "merchandise", 1600), ("Training shirt", "merchandise", 3200),
    ("Match ball — Dukes club special", "equipment", 2600), ("Match tea levy", "food", 500),
    ("Playing shirt (long sleeve)", "merchandise", 3800), ("Bowling machine hire (1 hour)", "kit_hire", 1500),
    ("Club hoodie", "merchandise", 3500), ("Winter nets — 10 session pass", "other", 4500),
]


def stock_shop(club: Club, count):
    tok = club.secretary.token()
    have = {p["name"] for p in rows(call("GET", f"/clubs/{club.id}/products", None, tok))}
    for name, category, cents in SHOP[:count]:
        if name not in have:
            call("POST", f"/clubs/{club.id}/products", {
                "name": name, "category": category, "price_cents": cents,
                "currency": "GBP", "stock": random.Random(name + club.slug).randint(6, 40)}, tok)


# ---------------------------------------------------------------------------


def write_manifest(hemel: Club, watford: Club, five, t20):
    """What the iOS tours need to know about this world, at a path the
    Simulator can read: who to sign in as, and who is playing tonight."""
    def side(club: Club, xi):
        rank = {"Fast Bowler": 0, "Spinner": 1, "All-rounder": 2}
        keeper = next(p for p in xi if p.position == "Wicketkeeper")
        bowlers = sorted((p for p in xi if p.position in rank),
                         key=lambda p: (rank[p.position], p.order))
        # Five overs, an over each: a side has to find five bowlers, and in a
        # game like that the part-timers get one.
        bowlers += [p for p in xi if p not in bowlers and p is not keeper][: max(0, 5 - len(bowlers))]
        return {
            "club": club.name, "name": club.short,
            "batting": [p.name for p in xi],
            "captain": club.captain_of(xi).name,
            "keeper": keeper.name,
            "bowlers": [p.name for p in bowlers],
        }
    manifest = {
        "password": PASSWORD,
        "hero": {"email": hemel.captain.email, "name": hemel.captain.name, "club": hemel.name},
        "watford_captain": {"email": watford.captain.email, "name": watford.captain.name},
        "super5s": {"event_id": five["id"], "title": five["title"],
                    "home": side(hemel, hemel.first_xi(9)), "away": side(watford, watford.first_xi(9))},
        "live_t20": {"event_id": t20["id"], "title": t20["title"]},
        "club_chat": f"{hemel.short} — club chat",
    }
    path = OPTS.manifest or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", ".dev", "seed-area.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(manifest, f, indent=2)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--invented", action="store_true",
                   help="invented club names — for a shared server, where a real club's name "
                        "does not belong on invented players and invented results")
    p.add_argument("--clubs", type=int, default=0, metavar="N",
                   help="seed about N clubs rather than the whole list (rounded to an even number "
                        "per league, so nobody sits out a round)")
    p.add_argument("--rounds", type=int, default=3, metavar="N",
                   help="Saturdays already played (default 3)")
    p.add_argument("--note", metavar="TEXT",
                   help="added to each club's description — say so when the data is a demo on a "
                        "server real people use")
    p.add_argument("--no-public-pages", dest="public_pages", action="store_false",
                   help="leave the clubs' public shop-window pages switched off")
    p.add_argument("--workers", type=int, metavar="N",
                   help="how many requests at once. Hashing a password is deliberately "
                        "memory-hungry, and a burst of signups can take a small server's API "
                        "over its memory limit — the default is 16 on loopback, 3 elsewhere")
    p.add_argument("--manifest", metavar="PATH",
                   help="where to write what the iOS tours read (default .dev/seed-area.json)")
    return p.parse_args()


def main():
    try:
        urllib.request.urlopen(API.rstrip("/") + "/health/ready", timeout=5).close()
    except Exception:
        raise SystemExit(f"No API at {API} — start it with ./scripts/start.sh first.")

    t0 = time.time()
    clubs = build_world()
    # Tonight's two fixtures need three clubs with a 2nd XI to draw on, so they
    # are the biggest, not whoever happens to be first in the list.
    big = sorted([c for c in clubs if len(c.men) >= 22], key=lambda c: -len(c.men))
    if len(big) < 3:
        raise SystemExit("this club list needs three clubs of 22 or more to field tonight's games")
    hemel, watford, kings = big[0], big[1], big[2]
    people = list(dict.fromkeys(p for c in clubs for p in [c.secretary] + c.men + c.women_squad))
    say(f"==> {len(clubs)} clubs, {len(people)} people — signing up")
    sign_everyone_up(people)

    say("==> clubs, grounds, teams and squads")
    parallel(set_up_club, clubs, workers=8)

    today = dt.datetime.now(LONDON).date()
    last_saturday = today - dt.timedelta(days=(today.weekday() - 5) % 7 or 7)
    next_saturday = last_saturday + dt.timedelta(days=7)
    played_on = [last_saturday - dt.timedelta(days=7 * n) for n in range(OPTS.rounds - 1, -1, -1)]

    played, upcoming = [], []
    # Whichever leagues this club list actually has, and however many rounds of
    # them have been played: the next Saturday is the round after those.
    for league in dict.fromkeys(c.league for c in clubs):
        rounds = round_robin([c for c in clubs if c.league == league])
        for number, day in enumerate(played_on, start=1):
            played += [(home, away, day, number) for home, away in rounds[(number - 1) % len(rounds)]]
        next_round = rounds[len(played_on) % len(rounds)]
        upcoming += [(home, away, next_saturday, len(played_on) + 1) for home, away in next_round]

    say(f"==> {len(played)} league matches, 40 overs a side, ball by ball")
    fixtures = parallel(lambda f: league_fixture(*f), played, workers=8)
    count = [0]

    def score(fx):
        state = play_match(fx)
        count[0] += 1
        say(f"  {count[0]:>2}/{len(fixtures)}  {fx['start']:%a %-d %b}  {fx['home'].short} v {fx['away'].short}"
            f" — {state.get('margin') or state['status']}")

    parallel(score, fixtures, workers=8)

    say("==> this Saturday's round, availability and nets")

    def this_saturday(f):
        fx = league_fixture(*f)
        rsvp(fx["event_id"], f[0].men[:16], seed=fx["event_id"])

    parallel(this_saturday, upcoming, workers=6)
    parallel(lambda c: mark_availability(c, [next_saturday, next_saturday + dt.timedelta(days=7)]), clubs, workers=4)

    tuesday = today + dt.timedelta(days=(1 - today.weekday()) % 7 or 7)
    thursday = today + dt.timedelta(days=(3 - today.weekday()) % 7 or 7)
    indoor = dt.date(today.year, 10, 1)
    indoor += dt.timedelta(days=(4 - indoor.weekday()) % 7)

    def nets(club: Club):
        for day, hour, title, venue in [(tuesday, 18, "Outdoor nets", club.venue_id),
                                        (thursday, 18, "Outdoor nets", club.venue_id),
                                        (indoor, 20, "Winter indoor nets", None)]:
            start = london(day, hour)
            event, created = find_or_create_event(club, title, {
                "event_subtype": "nets", "venue_id": venue, "start_at": iso(start),
                "end_at": iso(start + dt.timedelta(hours=2)), "capacity": 18, "fee_amount_cents": 500,
                "metadata": {"notes": "Bring your own kit; club balls provided."}})
            if created:
                rsvp(event["id"], club.men[:14], weights=(55, 25, 20), seed=event["id"])

    parallel(nets, clubs, workers=6)

    say("==> end-of-season dinners, shops and club chats")
    dinner = london(next_saturday + dt.timedelta(days=7), 19, 30)

    def dinner_night(club: Club):
        event, created = find_or_create_event(club, "End of season dinner & awards", {
            "event_subtype": "social", "venue_id": club.venue_id, "start_at": iso(dinner),
            "end_at": iso(dinner + dt.timedelta(hours=4, minutes=30)), "capacity": 90,
            "ticket_price_cents": 3500, "ticket_capacity": 90, "guests_allowed": 2,
            "metadata": {"notes": "Three courses, the awards and the raffle. Smart casual."}})
        if created:
            r = random.Random(f"dinner-{club.slug}")
            for p in r.sample(club.men + club.women_squad, 14):
                call("POST", f"/events/{event['id']}/tickets", {"guests": r.choice([0, 0, 1, 1, 2])}, p.token())

    parallel(dinner_night, [c for c in clubs if c.women or c is kings], workers=4)
    for index, club in enumerate(clubs):
        if club is hemel or index % 3 == 0:
            stock_shop(club, 8 if club is hemel else 4)
    parallel(club_chat, clubs, workers=6)

    say("==> today: a 2nd XI T20 in progress, and a 5-over game this evening")
    # A fixed time today, not "two hours ago": a second run has to recognise
    # the match it made the first time rather than start another one.
    t20_start = london(today, 16, 0)
    t20, _ = find_or_create_event(hemel, f"{hemel.short} 2nd XI v {kings.short} 2nd XI", {
        "event_subtype": "friendly", "opponent_club_id": kings.id, "team_id": hemel.teams["2nd XI"],
        "venue_id": hemel.venue_id, "start_at": iso(t20_start), "end_at": iso(t20_start + dt.timedelta(hours=3)),
        "capacity": 11, "metadata": {"opposition": f"{kings.short} 2nd XI", "home_name": f"{hemel.short} 2nd XI",
                                     "competition": "Midweek T20"}})
    live = {"home": hemel, "away": kings, "event_id": t20["id"], "start": t20_start, "overs": 20,
            "home_xi": hemel.second_xi(), "away_xi": kings.second_xi(), "scorer": hemel.second_captain,
            "home_name": f"{hemel.short} 2nd XI", "away_name": f"{kings.short} 2nd XI"}
    state = play_match(live, stop_second_innings_at=57)
    first, chase = state["innings"][0], state["innings"][-1]
    say(f"  T20: {first['runs']}/{first['wickets']} v {chase['runs']}/{chase['wickets']} "
        f"({chase['legal_balls'] // 6}.{chase['legal_balls'] % 6} overs) — {state['status']}")
    share = call("POST", f"/cricket/matches/{live['match_id']}/share", {"post_to_chat": False},
                 hemel.second_captain.token())

    evening = london(today, 18, 0)
    five, _ = find_or_create_event(hemel, f"{hemel.short} v {watford.short} — Super 5s", {
        "event_subtype": "friendly", "opponent_club_id": watford.id, "team_id": hemel.teams["1st XI"],
        "venue_id": hemel.venue_id, "start_at": iso(evening),
        "end_at": iso(evening + dt.timedelta(hours=1, minutes=30)), "capacity": 11, "fee_amount_cents": 500,
        "metadata": {"opposition": watford.short, "home_name": hemel.short,
                     "notes": "Five overs a side before the winter break."}})
    squad = hemel.first_xi(9)
    rsvp(five["id"], squad + hemel.men[11:13], weights=(100, 0, 0), seed="super-5s")
    call("POST", f"/events/{five['id']}/selection", {
        "selected": [p.id for p in squad], "reserves": [p.id for p in hemel.men[11:13] if p not in squad],
        "announcement": f"Super 5s v {watford.short} tonight — meet at 5:30, coloured kit.",
        "publish": True}, hemel.captain.token())
    # Everyone picked says they are playing, straight away: a same-day fixture
    # is already inside the drop window, and the job that clears unconfirmed
    # places would otherwise empty the side before anyone opened the app.
    parallel(lambda p: call("POST", f"/events/{five['id']}/selection/respond", {"confirming": True}, p.token()),
             squad, workers=11)

    write_manifest(hemel, watford, five, t20)
    try:
        balls = f"{psql('SELECT count(*) FROM cricket_scoring_events')} scoring events"
    except (subprocess.CalledProcessError, FileNotFoundError):
        balls = "ball by ball"   # not this machine's database
    say()
    say(f"Done in {time.time() - t0:.0f}s: {len(clubs)} clubs, {len(people)} players, "
        f"{len(fixtures)} league matches, {balls}.")
    say(f"Live T20 scoreboard: {share['url']}")
    say()
    say("Sign in with password123 as:")
    for person, what in [
        (hemel.captain, f"captain and secretary, {hemel.name}"),
        (hemel.second_captain, "2nd XI captain, scoring the live T20"),
        (watford.captain, f"captain, {watford.name}"),
        (hemel.men[0], f"opening bat, {hemel.name}"),
    ]:
        say(f"  {person.email:<34} {person.name} — {what}")
    say()
    say(f"Tonight at 18:00: {hemel.short} v {watford.short} — Super 5s at {hemel.ground}, not started.")


if __name__ == "__main__":
    OPTS = parse_args()
    if OPTS.workers is None:
        local = any(host in API for host in ("127.0.0.1", "localhost", "[::1]"))
        OPTS.workers = 16 if local else 3
    try:
        main()
    except ApiError as e:
        sys.exit(f"seed failed: {e}")
