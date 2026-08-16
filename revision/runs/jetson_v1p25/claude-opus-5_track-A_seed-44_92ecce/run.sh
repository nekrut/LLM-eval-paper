#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"
RAW="data/raw"
OUT="results"

mkdir -p "$OUT"

if [ ! -s "${REF}.fai" ]; then
    samtools faidx "$REF"
fi

if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.amb" ] || [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.pac" ] || [ ! -s "${REF}.sa" ]; then
    bwa index "$REF"
fi

for s in "${SAMPLES[@]}"; do
    r1="${RAW}/${s}_1.fq.gz"
    r2="${RAW}/${s}_2.fq.gz"
    bam="${OUT}/${s}.bam"
    bai="${OUT}/${s}.bam.bai"
    vcf="${OUT}/${s}.vcf"
    vcfgz="${OUT}/${s}.vcf.gz"
    tbi="${OUT}/${s}.vcf.gz.tbi"

    if [ ! -s "$bam" ] || [ "$r1" -nt "$bam" ] || [ "$r2" -nt "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${s}\tSM:${s}\tLB:${s}\tPL:ILLUMINA" \
            "$REF" "$r1" "$r2" \
        | samtools sort -@ "$THREADS" -o "${bam}.tmp"
        mv -f "${bam}.tmp" "$bam"
        rm -f "$bai"
    fi

    if [ ! -s "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [ ! -s "$vcfgz" ] || [ "$bam" -nt "$vcfgz" ]; then
        rm -f "$vcf" "$vcfgz" "$tbi"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
        bgzip -f "$vcf"
        rm -f "$tbi"
    fi

    if [ ! -s "$tbi" ] || [ "$vcfgz" -nt "$tbi" ]; then
        tabix -f -p vcf "$vcfgz"
    fi

    rm -f "$vcf"
done

TSV="${OUT}/collapsed.tsv"
REBUILD=0
if [ ! -s "$TSV" ]; then
    REBUILD=1
else
    for s in "${SAMPLES[@]}"; do
        if [ "${OUT}/${s}.vcf.gz" -nt "$TSV" ]; then
            REBUILD=1
        fi
    done
fi

if [ "$REBUILD" -eq 1 ]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for s in "${SAMPLES[@]}"; do
            bcftools query -f "${s}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT}/${s}.vcf.gz"
        done
    } > "${TSV}.tmp"
    mv -f "${TSV}.tmp" "$TSV"
fi