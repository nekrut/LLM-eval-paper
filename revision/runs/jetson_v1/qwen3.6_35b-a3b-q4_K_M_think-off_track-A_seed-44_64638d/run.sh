#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)
REF="data/ref/chrM.fa"

mkdir -p results

# 2. Reference indexing (once)
if [ ! -f "data/ref/chrM.fa.fai" ] || [ ! -f "data/ref/chrM.fa.bwt" ]; then
    samtools faidx "$REF"
    bwa index "$REF"
fi

# 3-7. Per-sample processing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="${vcf_gz}.tbi"

    # Skip if all outputs exist
    if [ -f "$bai" ] && [ -f "$tbi" ]; then
        continue
    fi

    # 3-4. Alignment and sorting
    if [ ! -f "$bam" ]; then
        bwa mem -t $THREADS \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "$REF" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" | \
        samtools sort -@ $THREADS -o "$bam" -
    fi

    # 5. BAM indexing
    if [ ! -f "$bai" ]; then
        samtools index -@ $THREADS "$bam"
    fi

    # 6-7. Variant calling, compression, indexing
    vcf_tmp="results/${sample}.vcf"
    if [ ! -f "$tbi" ] || [ "$vcf_gz" -ot "data/ref/chrM.fa" ] || [ "$vcf_gz" -ot "$bam" ]; then
        lofreq call-parallel -f "$REF" -r 4 -o "$vcf_tmp" -v "$bam"
        
        if [ ! -f "$vcf_gz" ] || [ "$vcf_gz" -ot "$vcf_tmp" ]; then
            bgzip -c "$vcf_tmp" > "$vcf_gz"
            rm -f "$vcf_tmp"
        fi
        
        if [ ! -f "$tbi" ] || [ "$tbi" -ot "$vcf_gz" ]; then
            tabix -p vcf "$vcf_gz"
        fi
    fi
done

# 8. Collapse step
collapsed="results/collapsed.tsv"
need_collapse=false
for sample in "${SAMPLES[@]}"; do
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        need_collapse=true
        break
    fi
done

if $need_collapse || [ ! -f "$collapsed" ]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${SAMPLES[@]}"; do
            bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi