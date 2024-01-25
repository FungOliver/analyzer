// PARAM: --set ana.activated[+] memOutOfBounds --set ana.activated[+] apron  --set ana.apron.domain polyhedra
#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>

int *gptr;
int len;

pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;

void *t_other(void *arg)
{
    pthread_mutex_lock(&mtx);
    for (int i = 0; i < len; i++)
    {
        gptr[i] = 42;     // NOWARN
        gptr[i + 1] = 42; // WARN
        gptr[i - 1] = 42; // WARN

        int tmp = gptr[i];     // NOWARN
        int tmp = gptr[i + 1]; // WARN
        int tmp = gptr[i - 1]; // WARN
    }
    pthread_mutex_unlock(&mtx);
}

int main()
{
    len = rand();
    len %= 10;
    gptr = malloc(sizeof(int) * len);

    pthread_t thread;
    pthread_create(&thread, NULL, t_other, NULL);

    pthread_mutex_lock(&mtx);
    for (int i = 0; i < len; i++)
    {
        gptr[i] = 42;     // NOWARN
        gptr[i + 1] = 42; // WARN
        gptr[i - 1] = 42; // WARN

        int tmp = gptr[i];     // NOWARN
        int tmp = gptr[i + 1]; // WARN
        int tmp = gptr[i - 1]; // WARN
    }
    pthread_mutex_unlock(&mtx);

    pthread_join(thread, NULL);
    free(gptr);
    return 0;
}