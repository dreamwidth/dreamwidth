#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "const-c.inc"

#include <sys/types.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <string.h>
#include <netinet/in.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#define GEN_UNSPEC 0
#define GEN_MALE   1
#define GEN_FEMALE 2

// 4b (country) + 4b state

struct meta {
  u_int32_t lastmod;      // 4 bytes

  u_int8_t  age;

  /* << 0 */
  u_int8_t  journaltype:2; // 0: person, 1: openid, 2: comm, 3: syn
  /* << 2 */
  u_int8_t  gender:2;      // 0: unspec, 1: male, 2: female
  /* << 4 */
  u_int8_t  status:2;      // single, looking, married, engaged, etc
  /* << 6 */
  u_int8_t  is_online:1;  /* or two bits?  web vs. jabber? */

  u_int8_t  regionid;   /* major region id */
  u_int8_t  unused;
};

#define METASIZE (sizeof(struct meta))

struct meta *usermeta = NULL;
unsigned int users     = 0;  /* how many users are set in usermeta */
unsigned int users_max = 0;  /* how large the memory allocated for usermeta array is.  max userid + 1 */

struct meta **resultset = NULL;
unsigned int resultset_size = 0;         /* matching items in resuletset */
size_t       resultset_mallocitems = 0;  /* how many items (not bytes!) we allocated resultset to be */
u_int8_t    *matchcount = NULL;  /* malloced array of set match count, aligning with resultset */

unsigned int sets_intersected = 0;

void init_new_search () {
  if (METASIZE != 8) {
    croak("METASIZE not 8!");
  }
  sets_intersected = 0;
}

void free_resultset () {
    if (resultset) {
      free(resultset);
      resultset = NULL;
      resultset_size = 0;
    }
}


void resultset_malloc_items (size_t items) {
  free_resultset();

  resultset = (struct meta **) malloc(sizeof(struct meta*) * items);
  resultset_size = 0;
  resultset_mallocitems = items;
}

void isect_begin (size_t len) {
  /* all we do at the beginning of an intersection is set the matching
     resultset to empty if this is the very first intersection */
  if (sets_intersected == 0)
    resultset_malloc_items(len);
}

void resultset_push (unsigned int uid) {
  if (resultset_size == resultset_mallocitems) {
    /* double malloced size */
    //printf("doubling from %d to %d\n", resultset_mallocitems, resultset_mallocitems*2);
    resultset_mallocitems *= 2;
    resultset = realloc(resultset, sizeof(struct meta*) * resultset_mallocitems);
  }
  resultset[resultset_size++] = &usermeta[uid];
}

void isect_scanning_isect (int(*test)(struct meta *)) {
  int i;
  int uid;

  if (sets_intersected == 0) {
    /* start small.  we'll double as needed. */
    resultset_malloc_items(256);

    /* not an off-by-one here, as users includes the index=0 user, which isn't a user */
    for (uid=1; uid<users; uid++) {
      if (test(&usermeta[uid])) {
        resultset_push(uid);
        matchcount[uid] = 1;
      }
    }
  } else {

    for (i=0; i<resultset_size; i++) {
      struct meta *m = resultset[i];
      if (test(m)) {
        unsigned int uid = ((u_int32_t)m - (u_int32_t)usermeta) / sizeof(struct meta);
        matchcount[uid]++;
      }
    }
  }

  sets_intersected++;
}

int min_modtime;
int test_modtime (struct meta *rec) {
  return rec->lastmod >= min_modtime;
}
void isect_updatetime_gte (unsigned int mintime) {
  min_modtime = mintime;
  isect_scanning_isect(test_modtime);
}

u_int8_t minage, maxage;
int test_age (struct meta *rec) {
  return rec->age >= minage && rec->age <= maxage;
}
void isect_age_range (u_int8_t age1, u_int8_t age2) {
  minage = age1;
  maxage = age2;
  isect_scanning_isect(test_age);
}

u_int8_t wanted_journaltype;
int test_journaltype (struct meta *rec) {
  return rec->journaltype == wanted_journaltype;
}
void isect_journal_type (u_int8_t jt) {
  wanted_journaltype = jt;
  isect_scanning_isect(test_journaltype);
}



/* region map must be 256 char string (no trailing null required, as
   it's just a true/value at each byte.  so yes, there will be nulls
   all over... it's not really a string) */
const unsigned char *okregion;
int test_region (struct meta *rec) {
  return okregion[rec->regionid];
}
void isect_region_map (const unsigned char *img, size_t len) {
  if (len != 256) {
    croak("provided isect_region_map string isn't 256 chars long");
  }
  okregion = img;
  isect_scanning_isect(test_region);
}


void isect_push (const unsigned char *img, size_t len) {
  unsigned int *uids = (unsigned int*) img;
  int i;
  int n = len / 4;

  //struct meta *m = &usermeta[ntohl(uids[i])];

  if (len % 4) {
    croak("Can't call isect/isect_push with strings not of 4 byte granularity");
  }

  if (sets_intersected == 0) {
    for (i=0; i<n; i++) {
      unsigned int uid = ntohl(uids[i]);
      if (uid < users_max) {
        // FIXME: this will kinda blow w/ 64-bit pointers... we should/could just store 32-bit id instead.
        resultset[resultset_size++] = &usermeta[uid];
        matchcount[uid] = 1;
      }
    }
  } else {
    for (i=0; i<n; i++) {
      unsigned int uid = ntohl(uids[i]);
      /* this gives us protection from dups in img */
      if (uid < users_max && matchcount[uid] == sets_intersected) {
        matchcount[uid]++;
      }
    }
  }

}

void isect_end () {
  sets_intersected++;
}

void isect (const unsigned char *img, size_t len) {
  isect_begin(len);
  isect_push(img, len);
  isect_end();
}

void dump_results () {
  int i;
  for (i=0; i<resultset_size; i++) {
    struct meta *m = resultset[i];
    unsigned int uid = ((u_int32_t)m - (u_int32_t)usermeta) / sizeof(struct meta);
    printf("uid %u = %u (of %u)\n", uid, matchcount[uid], sets_intersected);
    if (matchcount[uid]  == sets_intersected) {
      printf("Match on %d\n", uid);
    }
  }
}

static int
sort_by_modtime(const void *a1, const void *a2) {
  struct meta **u1_ptr = (struct meta **)a1;
  struct meta **u2_ptr = (struct meta **)a2;

  struct meta *u1 = *u1_ptr;
  struct meta *u2 = *u2_ptr;

  return (u2->lastmod > u1->lastmod) ? 1 :
    (u2->lastmod == u1->lastmod) ? 0 :
    -1;
}


AV* get_results () {
  int i;
  AV *av = newAV();
  struct meta *tmp;

  for (i=0; i<resultset_size; i++) {
    struct meta *m = resultset[i];
    unsigned int uid = ((u_int32_t)m - (u_int32_t)usermeta) / sizeof(struct meta);
    if (matchcount[uid] != sets_intersected) {
      resultset[i] = resultset[resultset_size - 1];
      i--;
      resultset_size--;
    }
  }

  // qsort remainder
  qsort(resultset, resultset_size, sizeof(struct meta *), sort_by_modtime);

  for (i=0; i<resultset_size; i++) {
    struct meta *m = resultset[i];
    unsigned int uid = ((u_int32_t)m - (u_int32_t)usermeta) / sizeof(struct meta);
    av_push(av, newSViv(uid));
  }

  sv_2mortal((SV*)av);
  return av;
}

void reset_usermeta (size_t len) {
  if (usermeta)
    free(usermeta);
  if (matchcount)
    free(matchcount);

  users     = 0;
  users_max = len / METASIZE;
  usermeta = (struct meta*) malloc(len);

  matchcount = (u_int8_t *) malloc(users_max);
}

int add_usermeta (const unsigned char *img, size_t len) {
  int i;
  unsigned int more = len / METASIZE;

  if (users + more > users_max)
    return 0;

  memcpy(&usermeta[users], img, len);

  for (i=users; i<users+more; i++) {
    struct meta *m = &usermeta[i];
    m->lastmod = ntohl(m->lastmod);
  }

  users += more;
  return 1;
}

void update_user (unsigned uid, const char *rec) {
  // don't update if new user outside our bounds, just drop it
  if (uid >= users_max) return;

  usermeta[uid] = *(struct meta *)rec;
}

#define FILE_READ_N  2048

int main () {
  FILE *imgfh;
  struct stat st;
  char readbuf[METASIZE * FILE_READ_N];
  size_t read = 0;
  size_t this_read;

  if (METASIZE != 8) {
    fprintf(stderr, "metasize not 8 bytes.\n");
    return 1;
  }

  imgfh = fopen("usermeta.img", "r");
  fstat(fileno(imgfh), &st);
  printf("file is = %u bytes\n", (unsigned int) st.st_size);

  reset_usermeta(st.st_size);
  while ((this_read = fread(readbuf, 8, FILE_READ_N, imgfh))) {
    add_usermeta(readbuf, this_read * METASIZE);
    read += (this_read * METASIZE);
  }
  if (read != st.st_size) {
    fprintf(stderr, "Failed to readall: %u instead of %llu\n", read, (long long) st.st_size);
    return(1);
  }

  printf("got: %d users, mod = %u\n", users, usermeta[1].lastmod);

  init_new_search();
  isect("\0\0\0\x04\0\0\0\x05\0\0\0\x07", 12);
  isect("\0\0\0\x08\0\0\0\x05\0\0\0\x07", 12);
  isect("\0\0\0\x04\0\0\0\x05\0\0\0\x07\0\0\0\x04", 16);
  dump_results();

  {
    int i;
    int match = 0;
    for (i=0; i<users; i++) {
      struct meta *m = &usermeta[i];
      if (m->lastmod & 0x01) {
        match++;
      }
    }
    printf("matches = %u\n", match);
  }

  return 0;
}


MODULE = LJ::UserSearch		PACKAGE = LJ::UserSearch		

INCLUDE: const-xs.inc

void
reset_usermeta (len)
     size_t len

int
add_usermeta (img, len)
     char* img
     size_t len

void
init_new_search ()

void
isect_begin (len)
     size_t len

void
isect_end ()

void
dump_results ()

AV*
get_results ()

void
isect_push (img)
     SV * img
   CODE:
      size_t len;
      const char *cdata = SvPV(img, len);
      isect_push(cdata, len);

void
isect (img)
     SV * img
   CODE:
      size_t len;
      const char *cdata = SvPV(img, len);
      isect(cdata, len);

void
isect_region_map (img)
     SV * img
   CODE:
      size_t len;
      const char *cdata = SvPV(img, len);
      isect_region_map(cdata, len);

void
update_user (uid, packdata)
     unsigned uid
     SV * packdata
   CODE:
     size_t len;
     const char *meta = SvPV(packdata, len);
     update_user(uid, meta);

void
isect_age_range (minage, maxage)
     int minage
     int maxage

void
isect_updatetime_gte (updatetime)
     unsigned int updatetime

void
isect_journal_type (jt)
     int jt
