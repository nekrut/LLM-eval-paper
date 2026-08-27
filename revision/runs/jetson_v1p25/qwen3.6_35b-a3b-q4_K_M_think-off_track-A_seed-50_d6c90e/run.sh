#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

REF_INDEX_FILES=(data/ref/chrM.fa.amb data/ref/chrM.fa.ann data/ref/chrM.fa.bwt data/ref/chrM.fa.pac data/ref/chrM.fa.sa)
need_bwa_index=0
for f in "${REF_INDEX_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        need_bwa_index=1
        break
    fi
done

if [ "$need_bwa_index" -eq 1 ]; then
    bwa index data/ref/chrM.fa
fi

# Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # 3 & 4. Alignment and sorting
    if [ ! -f "$bam" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ] || [ "data/raw/${sample}_2.fq.gz" -nt "$bam" ]; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ ${THREADS} -o "$bam" -
    fi

    # 5. BAM indexing
    if [ ! -f "$bai" ]; then
        samtools index -@ ${THREADS} "$bam"
    fi

    # 6. Variant calling with lofreq
    vcf="results/${sample}.vcf"
    if [ ! -f "$vcf_gz" ] || [ "$vcf" -nt "$vcf_gz" ]; then
        lofreq call-parallel --pp-threads ${THREADS} \
            -f data/ref/chrM.fa \
            -o "$vcf" \
            "$bam"
    fi

    # 7. VCF compression and indexing
    if [ ! -f "$vcf_gz" ] || [ "$vcf" -nt "$vcf_gz" ]; then
        bgzip -c "$vcf" > "$vcf_gz"
        tabix -p vcf "$vcf_gz"
        rm -f "$vcf"
    fi
done

# 8. Collapse step
collapsed="results/collapsed.tsv"
need_collapse=0
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz" ]; then
        need_collapse=1
        break
    fi
done

if [ "$need_collapse" -eq 0 ] && [ -f "$collapsed" ]; then
    for sample in "${SAMPLES[@]}"; do
        if [ "results/${sample}.vcf.gz" -nt "$collapsed" ]; then
            need_collapse=1
            break
        fi
    done
fi

if [ "$need_collapse" -eq 1 ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi