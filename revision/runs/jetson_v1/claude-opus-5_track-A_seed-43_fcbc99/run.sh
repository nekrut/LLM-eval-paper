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

for sample in "${SAMPLES[@]}"; do
    r1="${RAW}/${sample}_1.fq.gz"
    r2="${RAW}/${sample}_2.fq.gz"
    bam="${OUT}/${sample}.bam"
    bai="${OUT}/${sample}.bam.bai"
    vcf="${OUT}/${sample}.vcf"
    vcfgz="${OUT}/${sample}.vcf.gz"
    tbi="${OUT}/${sample}.vcf.gz.tbi"

    if [ ! -s "$bam" ] || [ "$r1" -nt "$bam" ] || [ "$r2" -nt "$bam" ]; then
        bwa mem -t "$THREADS" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" "$r1" "$r2" \
            | samtools sort -@ "$THREADS" -o "${bam}.tmp"
        mv "${bam}.tmp" "$bam"
        rm -f "$bai"
    fi

    if [ ! -s "$bai" ] || [ "$bam" -nt "$bai" ]; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [ ! -s "$vcfgz" ] || [ "$bam" -nt "$vcfgz" ]; then
        rm -f "$vcf" "${vcfgz}.tmp"
        lofreq call-parallel --pp-threads "$THREADS" -f "$REF" -o "$vcf" "$bam"
        bgzip -f -c "$vcf" > "${vcfgz}.tmp"
        mv "${vcfgz}.tmp" "$vcfgz"
        rm -f "$vcf"
        rm -f "$tbi"
    fi

    if [ ! -s "$tbi" ] || [ "$vcfgz" -nt "$tbi" ]; then
        tabix -f -p vcf "$vcfgz"
    fi
done

collapsed="${OUT}/collapsed.tsv"
rebuild=0
if [ ! -s "$collapsed" ]; then
    rebuild=1
else
    for sample in "${SAMPLES[@]}"; do
        if [ "${OUT}/${sample}.vcf.gz" -nt "$collapsed" ]; then
            rebuild=1
        fi
    done
fi

if [ "$rebuild" -eq 1 ]; then
    tmp="${collapsed}.tmp"
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$tmp"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${OUT}/${sample}.vcf.gz" >> "$tmp"
    done
    mv "$tmp" "$collapsed"
fi